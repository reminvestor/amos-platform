# frozen_string_literal: true

class CommunityEnergyPool < ApplicationRecord
  belongs_to :entity

  # Validations
  validates :entity_id, uniqueness: true
  validates :current_balance, numericality: { greater_than_or_equal_to: 0 }

  # ============================================
  # CLASS METHODS
  # ============================================

  def self.for_entity(entity)
    find_or_create_by!(entity: entity)
  end

  def self.deposit!(entity, amount)
    pool = for_entity(entity)
    pool.deposit!(amount)
  end

  def self.distribute!(entity)
    pool = for_entity(entity)
    pool.distribute!
  end

  # ============================================
  # INSTANCE METHODS
  # ============================================

  def deposit!(amount)
    return if amount <= 0

    update!(
      current_balance: current_balance + amount,
      total_deposited: total_deposited + amount
    )

    Rails.logger.info "[CommunityPool] Deposited #{amount.round(2)} energy for entity #{entity_id}. Balance: #{current_balance.round(2)}"
  end

  def distribute!
    return if current_balance < 10  # Minimum threshold for distribution

    # Find struggling agents
    struggling_agents = AgentPlugin.active
      .where(entity: entity)
      .joins(:energy_state)
      .where('agent_energy_states.current_energy < ?', 20)
      .where.not(status: 'in_school')

    return if struggling_agents.empty?

    # Calculate per-agent distribution
    per_agent = current_balance / struggling_agents.count
    per_agent = [per_agent, 10].min  # Cap at 10 per agent

    total_distributed = 0

    struggling_agents.each do |agent|
      agent.energy_state.earn!(
        per_agent,
        reason: 'community_redistribution'
      )
      total_distributed += per_agent
    end

    update!(
      current_balance: current_balance - total_distributed,
      total_distributed: self.total_distributed + total_distributed,
      distribution_count: distribution_count + 1,
      last_distribution_at: Time.current
    )

    Rails.logger.info "[CommunityPool] Distributed #{total_distributed.round(2)} energy to #{struggling_agents.count} agents"

    { distributed: total_distributed, recipients: struggling_agents.count }
  end

  # ============================================
  # STATISTICS
  # ============================================

  def health_status
    if current_balance > 100
      :healthy
    elsif current_balance > 50
      :moderate
    elsif current_balance > 10
      :low
    else
      :empty
    end
  end

  def distribution_frequency
    return nil if distribution_count.zero?

    days_active = (Time.current - created_at) / 1.day
    distribution_count / [days_active, 1].max
  end
end

