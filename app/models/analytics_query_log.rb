class AnalyticsQueryLog < ApplicationRecord
  # Execution cards - audit trail for all analytics queries
  
  belongs_to :entity
  belongs_to :user
  belongs_to :metric_definition, optional: true
  
  validates :metric_name, presence: true
  validates :query_hash, presence: true
  
  # Scopes
  scope :recent, -> { where('created_at >= ?', 1.hour.ago) }
  scope :by_metric, ->(metric_name) { where(metric_name: metric_name) }
  scope :by_entity, ->(entity_id) { where(entity_id: entity_id) }
  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }
  
  # Default values
  after_initialize :set_defaults, if: :new_record?
  
  # Get execution card (full audit trail)
  def execution_card
    {
      task_id: id,
      agent_id: metadata&.dig('agent_id'),
      tenant_id: entity_id,
      metric: metric_name,
      time_window: {
        start: query_params&.dig('start_date'),
        end: query_params&.dig('end_date'),
        grain: query_params&.dig('time_grain')
      },
      dimensions: query_params&.dig('group_by'),
      filters: query_params&.dig('where'),
      execution: {
        rows_returned: rows_returned,
        execution_time_ms: execution_time_ms,
        success: success,
        error: error_message
      },
      compiled_query_hash: query_hash,
      executed_at: created_at
    }
  end
  
  # Check if query was cached
  def from_cache?
    metadata&.dig('from_cache') == true
  end
  
  private
  
  def set_defaults
    self.success = false if success.nil?
    self.rows_returned ||= 0
    self.execution_time_ms ||= 0
    self.query_params ||= {}
    self.metadata ||= {}
  end
end

