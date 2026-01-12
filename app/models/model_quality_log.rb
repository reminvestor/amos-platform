# frozen_string_literal: true

# Tracks model quality events for reinforcement learning based model selection
# Used to learn which models work best for which tasks
class ModelQualityLog < ApplicationRecord
  belongs_to :entity, optional: true
  belongs_to :user, optional: true
  
  validates :model_id, presence: true
  validates :event_type, presence: true
  
  # Event types
  EVENTS = {
    json_parse_error: 'json_parse_error',       # Model produced invalid JSON
    tool_success: 'tool_success',               # Tool executed successfully
    tool_failure: 'tool_failure',               # Tool execution failed
    fallback_triggered: 'fallback_triggered',   # Had to fall back to another model
    streaming_error: 'streaming_error',         # Error during streaming
    context_overflow: 'context_overflow',       # Model hit context limits
    timeout: 'timeout',                         # Request timed out
    retry_success: 'retry_success',             # Retry succeeded
    retry_failure: 'retry_failure'              # Retry failed
  }.freeze
  
  scope :for_model, ->(model_id) { where(model_id: model_id) }
  scope :errors, -> { where(event_type: %w[json_parse_error tool_failure streaming_error context_overflow timeout]) }
  scope :successes, -> { where(event_type: %w[tool_success retry_success]) }
  scope :recent, -> { where('created_at > ?', 7.days.ago) }
  
  # Calculate success rate for a model
  def self.success_rate_for(model_id, tool_name: nil, days: 7)
    scope = for_model(model_id).where('created_at > ?', days.days.ago)
    scope = scope.where(tool_name: tool_name) if tool_name
    
    total = scope.count
    return nil if total < 10 # Not enough data
    
    successes = scope.successes.count
    (successes.to_f / total * 100).round(1)
  end
  
  # Get models ranked by performance for a specific tool
  def self.best_models_for_tool(tool_name, days: 7)
    sql = <<-SQL
      SELECT model_id,
             COUNT(*) as total_calls,
             SUM(CASE WHEN event_type IN ('tool_success', 'retry_success') THEN 1 ELSE 0 END) as successes,
             AVG(latency_ms) as avg_latency,
             (SUM(CASE WHEN event_type IN ('tool_success', 'retry_success') THEN 1 ELSE 0 END)::float / COUNT(*)) as success_rate
      FROM model_quality_logs
      WHERE tool_name = ?
        AND created_at > ?
      GROUP BY model_id
      HAVING COUNT(*) >= 5
      ORDER BY success_rate DESC, avg_latency ASC
    SQL
    
    find_by_sql([sql, tool_name, days.days.ago])
  end
  
  # Get error patterns for a model
  def self.error_patterns_for(model_id, days: 7)
    for_model(model_id)
      .errors
      .where('created_at > ?', days.days.ago)
      .group(:event_type, :tool_name)
      .count
  end
  
  # Suggest best model for a tool based on historical performance
  def self.suggest_model_for(tool_name, current_model: nil, days: 7)
    rankings = best_models_for_tool(tool_name, days: days)
    return nil if rankings.empty?
    
    # Filter out current model if it's failing
    if current_model
      current_stats = rankings.find { |r| r.model_id == current_model }
      if current_stats && current_stats.success_rate < 0.7
        # Current model is underperforming, suggest better one
        better = rankings.find { |r| r.model_id != current_model && r.success_rate > 0.85 }
        return better&.model_id
      end
    end
    
    rankings.first&.model_id
  end
end

