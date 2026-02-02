# frozen_string_literal: true

# ExternalAgentToolCall - Audit log for external agent tool usage
#
# Every tool call made by an external agent is logged here for:
# - Security auditing
# - Debugging failed executions
# - Analyzing agent behavior patterns
# - Policy compliance verification
#
class ExternalAgentToolCall < ApplicationRecord
  # Associations
  belongs_to :external_agent_execution
  belongs_to :external_agent_registration

  # Validations
  validates :tool_name, presence: true
  validates :executed_at, presence: true

  # Scopes
  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }
  scope :policy_blocked, -> { where(policy_allowed: false) }
  scope :by_tool, ->(name) { where(tool_name: name) }
  scope :recent, -> { order(executed_at: :desc) }
  scope :today, -> { where('executed_at >= ?', Time.current.beginning_of_day) }

  # Class methods for analytics
  class << self
    def usage_by_tool(since: 24.hours.ago)
      where('executed_at >= ?', since)
        .group(:tool_name)
        .count
        .sort_by { |_, count| -count }
    end

    def failure_rate_by_tool(since: 24.hours.ago)
      calls = where('executed_at >= ?', since).group(:tool_name)
      total = calls.count
      failed = calls.where(success: false).count

      total.map do |tool, count|
        failure_count = failed[tool] || 0
        [tool, { total: count, failed: failure_count, rate: (failure_count.to_f / count * 100).round(1) }]
      end.to_h
    end

    def average_latency_by_tool(since: 24.hours.ago)
      where('executed_at >= ?', since)
        .where.not(latency_ms: nil)
        .group(:tool_name)
        .average(:latency_ms)
        .transform_values { |v| v.round(0) }
    end
  end

  def to_log_entry
    {
      tool: tool_name,
      success: success,
      latency_ms: latency_ms,
      policy_allowed: policy_allowed,
      executed_at: executed_at.iso8601
    }
  end
end
