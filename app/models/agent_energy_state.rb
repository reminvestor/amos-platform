# frozen_string_literal: true

class AgentEnergyState < ApplicationRecord
  belongs_to :agent_plugin
  belongs_to :entity
  has_many :transactions, class_name: 'AgentEnergyTransaction', foreign_key: :agent_plugin_id, primary_key: :agent_plugin_id

  # Constants
  MAX_DEBT = -50.0
  INTEREST_RATE = 0.05  # 5% per hour when in debt

  # Validations
  validates :current_energy, presence: true
  validates :max_energy, presence: true, numericality: { greater_than: 0 }
  validates :agent_plugin_id, uniqueness: true

  # Scopes
  scope :struggling, -> { where('current_energy < ?', 20) }
  scope :healthy, -> { where('current_energy >= ?', 50) }
  scope :in_debt, -> { where(in_debt: true) }
  scope :can_help, -> { where('current_energy >= ?', 30) }

  # Callbacks
  after_initialize :set_defaults, if: :new_record?

  # ============================================
  # ENERGY OPERATIONS
  # ============================================

  def earn!(amount, reason:, execution: nil, request: nil)
    return if amount <= 0

    # Apply progressive taxation for high-energy agents
    taxed_amount = apply_progressive_tax(amount)
    tax_paid = amount - taxed_amount

    transaction do
      before = current_energy
      new_energy = [current_energy + taxed_amount, max_energy].min

      update!(
        current_energy: new_energy,
        total_earned: total_earned + taxed_amount,
        in_debt: new_energy < 0,
        last_energy_update_at: Time.current
      )

      record_transaction!(
        type: 'earned',
        amount: taxed_amount,
        reason: reason,
        before: before,
        after: new_energy,
        execution: execution,
        request: request,
        metadata: { original_amount: amount, tax_paid: tax_paid }
      )

      # Deposit tax to community pool
      if tax_paid > 0
        CommunityEnergyPool.deposit!(entity, tax_paid)
      end
    end

    current_energy
  end

  def spend!(amount, reason:, request: nil)
    raise InsufficientEnergyError, "Need #{amount}, have #{current_energy}" if current_energy - amount < MAX_DEBT

    transaction do
      before = current_energy
      new_energy = current_energy - amount

      update!(
        current_energy: new_energy,
        total_spent: total_spent + amount,
        in_debt: new_energy < 0,
        debt_started_at: new_energy < 0 && !in_debt ? Time.current : debt_started_at,
        last_energy_update_at: Time.current
      )

      record_transaction!(
        type: 'spent',
        amount: -amount,
        reason: reason,
        before: before,
        after: new_energy,
        request: request
      )
    end

    current_energy
  end

  def penalize!(amount, reason:, execution: nil)
    transaction do
      before = current_energy
      new_energy = [current_energy - amount, MAX_DEBT].max

      update!(
        current_energy: new_energy,
        in_debt: new_energy < 0,
        debt_started_at: new_energy < 0 && !in_debt ? Time.current : debt_started_at,
        last_energy_update_at: Time.current
      )

      record_transaction!(
        type: 'penalty',
        amount: -amount,
        reason: reason,
        before: before,
        after: new_energy,
        execution: execution
      )

      # Check if agent needs to go to school
      # Only enroll if:
      # 1. Energy is critically low (below -20, not just 0)
      # 2. OR agent has failed 3+ times recently AND energy is below 10
      should_enroll = false

      if new_energy <= -20
        # Critically low - definitely needs school
        should_enroll = true
        Rails.logger.warn "[AgentEnergyState] Agent #{agent_plugin_id} critically low energy (#{new_energy}), enrolling in school"
      elsif new_energy <= 10 && tasks_failed >= 3
        # Low energy + multiple failures
        recent_failures = agent_plugin.agent_plugin_executions
          .where(status: 'failed')
          .where('created_at > ?', 24.hours.ago)
          .count

        if recent_failures >= 3
          should_enroll = true
          Rails.logger.warn "[AgentEnergyState] Agent #{agent_plugin_id} has #{recent_failures} recent failures and low energy (#{new_energy}), enrolling in school"
        end
      end

      if should_enroll
        AgentSchoolEnrollmentJob.perform_later(agent_plugin_id)
      end
    end

    current_energy
  end

  def regenerate!
    return if last_energy_update_at.nil?
    return if current_energy >= max_energy

    hours_elapsed = (Time.current - last_energy_update_at) / 1.hour
    return if hours_elapsed < 0.1  # Don't update for tiny intervals

    # Non-linear regeneration: high energy = slower regen
    effective_rate = calculate_regeneration_rate
    regen_amount = hours_elapsed * effective_rate

    # Apply interest if in debt
    if in_debt?
      debt_hours = (Time.current - debt_started_at) / 1.hour
      interest = current_energy.abs * INTEREST_RATE * debt_hours
      regen_amount -= interest
    end

    return if regen_amount.abs < 0.1

    transaction do
      before = current_energy
      new_energy = [current_energy + regen_amount, max_energy].min

      update!(
        current_energy: new_energy,
        in_debt: new_energy < 0,
        last_energy_update_at: Time.current
      )

      record_transaction!(
        type: 'regenerated',
        amount: regen_amount,
        reason: in_debt? ? 'regeneration_with_interest' : 'passive_regeneration',
        before: before,
        after: new_energy
      )
    end
  end

  # ============================================
  # CAPABILITY CHECKS
  # ============================================

  def can_ask_for_help?
    current_energy >= 2  # Minimum cost for advice
  end

  def can_delegate?
    current_energy >= 10  # Minimum cost for subtask delegation
  end

  def should_try_solo?
    current_energy < 20  # Low energy, need to earn
  end

  def can_help_others?
    current_energy >= 30 && !agent_plugin.in_school?
  end

  # ============================================
  # STATISTICS
  # ============================================

  def update_stats!(success:, quality: 0.5)
    new_tasks = tasks_completed + (success ? 1 : 0)
    new_failed = tasks_failed + (success ? 0 : 1)
    total = new_tasks + new_failed

    new_success_rate = total > 0 ? new_tasks.to_f / total : 0.0
    new_avg_quality = ((avg_quality * (total - 1)) + quality) / total

    update!(
      tasks_completed: new_tasks,
      tasks_failed: new_failed,
      success_rate: new_success_rate,
      avg_quality: new_avg_quality
    )
  end

  def update_elo!(opponent_difficulty, actual_outcome)
    # Elo rating update for slow-moving reputation
    expected = 1.0 / (1 + 10**((opponent_difficulty - elo_rating) / 400.0))
    k_factor = [32 - (tasks_completed / 100), 8].max

    new_rating = elo_rating + k_factor * (actual_outcome - expected)
    update!(elo_rating: new_rating)
  end

  private

  def set_defaults
    self.current_energy ||= 75.0  # Start with more energy to allow learning
    self.max_energy ||= 100.0
    self.regeneration_rate ||= 3.0  # Faster base regeneration
    self.last_energy_update_at ||= Time.current
  end

  def calculate_regeneration_rate
    # Non-linear: struggling agents regenerate faster to encourage recovery
    if current_energy < 20
      5.0  # Very fast regeneration when critically low
    elsif current_energy < 40
      4.0  # Fast regeneration when struggling
    elsif current_energy < 60
      3.0  # Normal regeneration
    elsif current_energy < 80
      2.0  # Slower regeneration
    else
      1.0  # Slow - encourage spending
    end
  end

  def apply_progressive_tax(amount)
    # Tax brackets based on current energy
    if current_energy >= 90
      amount * 0.7  # 30% tax
    elsif current_energy >= 75
      amount * 0.8  # 20% tax
    elsif current_energy >= 50
      amount * 0.9  # 10% tax
    else
      amount  # No tax when struggling
    end
  end

  def record_transaction!(type:, amount:, reason:, before:, after:, execution: nil, request: nil, metadata: {})
    last_tx = AgentEnergyTransaction.where(agent_plugin_id: agent_plugin_id).order(created_at: :desc).first

    tx = AgentEnergyTransaction.create!(
      agent_plugin_id: agent_plugin_id,
      entity_id: entity_id,
      agent_plugin_execution_id: execution&.id,
      collaboration_request_id: request&.id,
      transaction_type: type,
      amount: amount,
      reason: reason,
      balance_before: before,
      balance_after: after,
      metadata: metadata,
      previous_ledger_hash: last_tx&.ledger_hash
    )

    # Calculate hash for immutable ledger
    tx.update_column(:ledger_hash, tx.calculate_ledger_hash)
  end
end

class InsufficientEnergyError < StandardError; end

