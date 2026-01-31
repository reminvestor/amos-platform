# frozen_string_literal: true

# RevenueDistribution tracks each periodic revenue share event
class RevenueDistribution < ApplicationRecord
  has_many :revenue_payments, dependent: :nullify

  validates :period, presence: true, uniqueness: true
  validates :gross_revenue, presence: true, numericality: { greater_than: 0 }
  validates :holder_pool, presence: true, numericality: { greater_than_or_equal_to: 0 }

  scope :recent, -> { order(distributed_at: :desc) }
  scope :for_year, ->(year) { where('period LIKE ?', "#{year}-%") }

  def usdc_percentage
    return 0 if holder_pool.zero?
    (usdc_distributed / holder_pool * 100).round(2)
  end

  def buyback_percentage
    return 0 if holder_pool.zero?
    100 - usdc_percentage
  end

  def average_payout
    return 0 if recipients_count.zero?
    (usdc_distributed / recipients_count).round(2)
  end
end
