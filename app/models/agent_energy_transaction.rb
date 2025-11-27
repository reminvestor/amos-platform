# frozen_string_literal: true

class AgentEnergyTransaction < ApplicationRecord
  belongs_to :agent_plugin
  belongs_to :entity
  belongs_to :agent_plugin_execution, optional: true
  belongs_to :collaboration_request, class_name: 'AgentCollaborationRequest', optional: true

  # Transaction types
  EARN_TYPES = %w[earned task_completion quality_bonus speed_bonus user_satisfaction helped_agent].freeze
  SPEND_TYPES = %w[spent ask_advice delegate_subtask full_delegation].freeze
  PENALTY_TYPES = %w[penalty task_failure timeout retry_needed collusion_detected].freeze
  SYSTEM_TYPES = %w[regenerated tax redistribution].freeze

  ALL_TYPES = (EARN_TYPES + SPEND_TYPES + PENALTY_TYPES + SYSTEM_TYPES).freeze

  # Validations
  validates :transaction_type, presence: true, inclusion: { in: ALL_TYPES }
  validates :amount, presence: true
  validates :reason, presence: true
  validates :balance_before, presence: true
  validates :balance_after, presence: true

  # Scopes
  scope :earnings, -> { where(transaction_type: EARN_TYPES) }
  scope :spending, -> { where(transaction_type: SPEND_TYPES) }
  scope :penalties, -> { where(transaction_type: PENALTY_TYPES) }
  scope :recent, ->(hours = 24) { where('created_at > ?', hours.hours.ago) }
  scope :for_agent, ->(agent) { where(agent_plugin: agent) }

  # Calculate hash for immutable ledger
  def calculate_ledger_hash
    data = "#{agent_plugin_id}:#{amount}:#{created_at.to_i}:#{previous_ledger_hash}"
    Digest::SHA256.hexdigest(data)
  end

  # Verify chain integrity
  def self.verify_chain_integrity!(agent_plugin_id)
    transactions = where(agent_plugin_id: agent_plugin_id).order(:id)

    transactions.each_cons(2) do |prev, curr|
      expected_hash = curr.calculate_hash_with_previous(prev.ledger_hash)

      if curr.ledger_hash != expected_hash
        raise LedgerTamperingDetected, "Transaction #{curr.id} has been tampered with!"
      end
    end

    true
  end

  def calculate_hash_with_previous(prev_hash)
    data = "#{agent_plugin_id}:#{amount}:#{created_at.to_i}:#{prev_hash}"
    Digest::SHA256.hexdigest(data)
  end

  # Forensic analysis
  def self.forensic_analysis(agent, time_range)
    entries = where(agent_plugin: agent)
      .where(created_at: time_range)
      .order(:created_at)

    {
      total_earned: entries.where('amount > 0').sum(:amount),
      total_spent: entries.where('amount < 0').sum(:amount).abs,
      net_flow: entries.sum(:amount),
      transaction_count: entries.count,
      largest_gain: entries.maximum(:amount),
      largest_loss: entries.minimum(:amount),
      by_type: entries.group(:transaction_type).sum(:amount),
      suspicious_patterns: detect_forensic_anomalies(entries)
    }
  end

  def self.detect_forensic_anomalies(entries)
    anomalies = []

    # Check for unusual earning patterns
    hourly_earnings = entries.earnings.group_by_hour(:created_at).sum(:amount)
    avg_hourly = hourly_earnings.values.sum / [hourly_earnings.size, 1].max

    hourly_earnings.each do |hour, amount|
      if amount > avg_hourly * 3
        anomalies << { type: :unusual_earnings, hour: hour, amount: amount }
      end
    end

    # Check for rapid transactions
    entries.each_cons(2) do |prev, curr|
      if (curr.created_at - prev.created_at) < 1.second
        anomalies << { type: :rapid_transactions, ids: [prev.id, curr.id] }
      end
    end

    anomalies
  end
end

class LedgerTamperingDetected < StandardError; end

