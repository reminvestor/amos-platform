# app/models/entity_usage_metric.rb
class EntityUsageMetric < ApplicationRecord
  belongs_to :entity

  validates :category, presence: true
  validates :service, presence: true
  validates :tracked_at, presence: true

  # Scopes for reporting
  scope :for_date_range, ->(start_date, end_date) {
    where(tracked_at: start_date..end_date)
  }

  scope :by_category, ->(category) { where(category: category) }
  scope :by_service, ->(service) { where(service: service) }

  scope :recent, -> { where('tracked_at >= ?', 30.days.ago) }
  scope :this_month, -> { where('tracked_at >= ?', Time.current.beginning_of_month) }
  scope :this_week, -> { where('tracked_at >= ?', Time.current.beginning_of_week) }
  scope :today, -> { where('tracked_at >= ?', Time.current.beginning_of_day) }

  # Calculate total cost for a collection of metrics
  def self.total_cost
    sum(:calculated_cost_usd)
  end

  # Group metrics by category
  def self.group_by_category
    group(:category).sum(:calculated_cost_usd)
  end

  # Group metrics by service
  def self.group_by_service
    group(:service).sum(:calculated_cost_usd)
  end

  # Get daily totals
  def self.daily_totals(days = 30)
    where('tracked_at >= ?', days.days.ago)
      .group("DATE(tracked_at)")
      .sum(:calculated_cost_usd)
  end
end
