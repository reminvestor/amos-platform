# frozen_string_literal: true

# Immutable ledger of all token stake movements
# Provides complete audit trail for transparency
class TokenStakeTransaction < ApplicationRecord
  belongs_to :token_stake
  belongs_to :user

  # Transaction types
  TRANSACTION_TYPES = %w[earn decay transfer burn vest withdrawal deposit claim clawback].freeze

  validates :transaction_type, presence: true, inclusion: { in: TRANSACTION_TYPES }
  validates :amount, presence: true
  validates :balance_before, presence: true
  validates :balance_after, presence: true

  # Scopes
  scope :earnings, -> { where(transaction_type: 'earn') }
  scope :decays, -> { where(transaction_type: 'decay') }
  scope :transfers, -> { where(transaction_type: 'transfer') }
  scope :for_user, ->(user) { where(user: user) }
  scope :recent, -> { order(created_at: :desc) }
  scope :in_date_range, ->(start_date, end_date) { where(created_at: start_date..end_date) }

  # Class methods for aggregation
  class << self
    def total_earned
      earnings.sum(:amount)
    end

    def total_decayed
      decays.sum('ABS(amount)')
    end

    def daily_activity(days: 30)
      where('created_at >= ?', days.days.ago)
        .group('DATE(created_at)')
        .group(:transaction_type)
        .sum(:amount)
    end
  end
end
