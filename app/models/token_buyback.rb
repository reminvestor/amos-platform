# frozen_string_literal: true

# TokenBuyback tracks buyback and burn operations
class TokenBuyback < ApplicationRecord
  STATUSES = %w[pending executing completed failed].freeze

  validates :period, presence: true
  validates :usdc_amount, presence: true, numericality: { greater_than: 0 }
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: 'pending') }
  scope :completed, -> { where(status: 'completed') }
  scope :for_period, ->(period) { where(period: period) }
  scope :recent, -> { order(created_at: :desc) }

  def execute!
    update!(status: 'executing')
    
    # In production, this would:
    # 1. Call Jupiter API to swap USDC for AMOS
    # 2. Burn the acquired tokens
    # 3. Record the transaction signatures
    
    # For now, mark as completed with estimated values
    update!(
      status: 'completed',
      actual_tokens_bought: estimated_tokens,
      executed_at: Time.current
    )
  end

  def tokens_burned
    actual_tokens_bought || estimated_tokens || 0
  end

  def effective_price
    return 0 if tokens_burned.zero?
    (usdc_amount / tokens_burned).round(6)
  end
end
