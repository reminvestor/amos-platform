# ToolUsageMetric
#
# Tracks usage of tools across the system for analytics and prioritization.
# This data is used by TieredDiscoveryService to boost frequently-used tools.
#
class ToolUsageMetric < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :entity, optional: true
  belongs_to :tool_definition, optional: true

  validates :tool_name, presence: true

  # Scopes
  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }
  scope :recent, -> { where("created_at > ?", 30.days.ago) }
  scope :for_entity, ->(entity) { where(entity: entity) }
  scope :for_user, ->(user) { where(user: user) }
  scope :for_tool, ->(name) { where(tool_name: name) }

  # Class methods for analytics

  # Get most used tools for an entity
  def self.top_tools_for_entity(entity, limit: 20)
    for_entity(entity)
      .successful
      .recent
      .group(:tool_name)
      .order("count_all DESC")
      .limit(limit)
      .count
  end

  # Get most used tools for a user
  def self.top_tools_for_user(user, limit: 20)
    for_user(user)
      .successful
      .recent
      .group(:tool_name)
      .order("count_all DESC")
      .limit(limit)
      .count
  end

  # Get tool success rate
  def self.success_rate_for_tool(tool_name, entity: nil)
    scope = for_tool(tool_name).recent
    scope = scope.for_entity(entity) if entity

    total = scope.count
    return 0.0 if total.zero?

    successful = scope.successful.count
    (successful.to_f / total * 100).round(2)
  end

  # Get average latency for a tool
  def self.average_latency_for_tool(tool_name, entity: nil)
    scope = for_tool(tool_name).recent.where.not(latency_ms: nil)
    scope = scope.for_entity(entity) if entity

    scope.average(:latency_ms)&.round(0) || 0
  end

  # Get usage trend (daily counts for last N days)
  def self.usage_trend(tool_name: nil, entity: nil, days: 30)
    scope = recent
    scope = scope.for_tool(tool_name) if tool_name
    scope = scope.for_entity(entity) if entity

    scope
      .group("DATE(created_at)")
      .order("DATE(created_at)")
      .count
  end

  # Record a tool usage
  def self.record(tool_name:, user: nil, entity: nil, tool_definition: nil, tool_type: nil, success: true, latency_ms: nil, context: nil, agent_slug: nil, metadata: {})
    create(
      tool_name: tool_name,
      user: user,
      entity: entity,
      tool_definition: tool_definition,
      tool_type: tool_type || determine_tool_type(tool_name, tool_definition),
      success: success,
      latency_ms: latency_ms,
      context: context,
      agent_slug: agent_slug,
      metadata: metadata
    )
  rescue => e
    Rails.logger.error "Failed to record tool usage metric: #{e.message}"
    nil
  end

  private

  def self.determine_tool_type(tool_name, tool_definition)
    return "definition" if tool_definition.present?
    
    catalog = Tools::ToolCatalog.instance
    tool_info = catalog.tools[tool_name]
    
    case tool_info&.dig(:type)
    when :class then "class"
    when :definition then "definition"
    else "unknown"
    end
  end
end

