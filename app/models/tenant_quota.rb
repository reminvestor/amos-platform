class TenantQuota < ApplicationRecord
  belongs_to :entity
  
  validates :entity_id, uniqueness: true
  validates :row_budget, numericality: { greater_than: 0 }
  validates :window_days_cap, numericality: { greater_than: 0 }
  validates :qps_limit, numericality: { greater_than: 0 }
  
  # Default values
  after_initialize :set_defaults, if: :new_record?
  
  # Check if within budget
  def within_budget?(estimated_rows)
    estimated_rows <= row_budget
  end
  
  # Check if time window is allowed
  def window_allowed?(start_date, end_date)
    days = (end_date.to_date - start_date.to_date).to_i
    days <= window_days_cap
  end
  
  # Check rate limit
  def within_rate_limit?
    recent_queries = AnalyticsQueryLog
      .where(entity: entity)
      .where('created_at >= ?', 1.second.ago)
      .count
    
    recent_queries < qps_limit
  end
  
  # Get current usage
  def current_usage(time_window = 1.hour)
    {
      queries_count: AnalyticsQueryLog.where(entity: entity).where('created_at >= ?', time_window.ago).count,
      rows_scanned: AnalyticsQueryLog.where(entity: entity).where('created_at >= ?', time_window.ago).sum(:rows_returned),
      usage_percentage: (AnalyticsQueryLog.where(entity: entity).where('created_at >= ?', time_window.ago).sum(:rows_returned).to_f / row_budget * 100).round(2)
    }
  end
  
  private
  
  def set_defaults
    self.row_budget ||= 1_000_000  # 1M rows per query
    self.window_days_cap ||= 400   # Max 400 days per query
    self.qps_limit ||= 10          # 10 queries per second
    self.metadata ||= {}
  end
end

