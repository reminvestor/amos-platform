# frozen_string_literal: true

# RevenuePayment tracks individual revenue share payments to users
class RevenuePayment < ApplicationRecord
  belongs_to :user
  belongs_to :revenue_distribution, optional: true

  STATUSES = %w[pending credited transferred failed].freeze
  PAYMENT_METHODS = %w[platform_credit solana_transfer bank_transfer].freeze

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true
  validates :period, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: 'pending') }
  scope :completed, -> { where(status: %w[credited transferred]) }
  scope :for_period, ->(period) { where(period: period) }
  scope :recent, -> { order(created_at: :desc) }

  def complete!(transaction_signature: nil)
    update!(
      status: transaction_signature ? 'transferred' : 'credited',
      transaction_signature: transaction_signature,
      paid_at: Time.current
    )
  end

  def fail!(reason: nil)
    update!(
      status: 'failed',
      metadata: metadata.merge(failure_reason: reason)
    )
  end
end
