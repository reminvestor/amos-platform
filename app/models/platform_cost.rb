# frozen_string_literal: true

# PlatformCost
#
# Tracks real platform operating costs for dynamic decay calculation.
# This creates transparency: token decay directly reflects platform economics.
#
class PlatformCost < ApplicationRecord
  CATEGORIES = %w[compute infrastructure third_party personnel marketing legal other].freeze
  PERIOD_TYPES = %w[one_time monthly quarterly annual].freeze

  belongs_to :recorded_by, class_name: 'User', optional: true

  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :recorded_at, presence: true
  validates :period_type, inclusion: { in: PERIOD_TYPES }

  scope :in_period, ->(start_date, end_date) {
    where('recorded_at >= ? AND recorded_at <= ?', start_date, end_date)
  }
  
  scope :by_category, ->(category) { where(category: category) }
  scope :monthly, -> { where(period_type: 'monthly') }
  scope :one_time, -> { where(period_type: 'one_time') }

  # Get total costs for a period
  def self.total_for_period(start_date, end_date = Time.current)
    in_period(start_date, end_date).sum(:amount)
  end

  # Get costs breakdown by category
  def self.breakdown_by_category(start_date, end_date = Time.current)
    in_period(start_date, end_date)
      .group(:category)
      .sum(:amount)
  end

  # Estimate monthly recurring costs
  def self.estimated_monthly_recurring
    monthly.where('recorded_at > ?', 3.months.ago)
           .group(:description)
           .average(:amount)
           .values
           .sum
  end
end
