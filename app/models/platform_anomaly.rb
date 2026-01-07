# frozen_string_literal: true

# PlatformAnomaly - Detected anomalies in platform operation
#
# Anomalies are unusual patterns or issues detected during perception.
# They can trigger autonomous actions, goals, or alerts.
#
# Anomaly Types:
# - performance_drop: Sudden decrease in success rate or increase in latency
# - error_spike: Unusual increase in errors
# - resource_anomaly: Unusual resource consumption
# - behavior_change: Unexpected change in agent behavior
# - capacity_issue: Overloaded agents or tools
#
class PlatformAnomaly < ApplicationRecord
  belongs_to :entity
  belongs_to :platform_perception, optional: true
  belongs_to :triggered_goal, class_name: 'AgentGoal', optional: true

  ANOMALY_TYPES = %w[performance_drop error_spike resource_anomaly behavior_change capacity_issue stale_agent].freeze
  SEVERITIES = %w[low medium high critical].freeze
  STATUSES = %w[detected investigating resolved ignored].freeze

  validates :anomaly_type, presence: true, inclusion: { in: ANOMALY_TYPES }
  validates :severity, presence: true, inclusion: { in: SEVERITIES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :title, presence: true

  scope :detected, -> { where(status: 'detected') }
  scope :investigating, -> { where(status: 'investigating') }
  scope :resolved, -> { where(status: 'resolved') }
  scope :ignored, -> { where(status: 'ignored') }
  scope :active, -> { where(status: %w[detected investigating]) }
  scope :by_severity, ->(severity) { where(severity: severity) }
  scope :critical, -> { by_severity('critical') }
  scope :high_or_critical, -> { where(severity: %w[high critical]) }
  scope :by_type, ->(type) { where(anomaly_type: type) }
  scope :for_target, ->(type, id) { where(target_type: type, target_id: id) }
  scope :recent, -> { order(created_at: :desc) }
  scope :unresolved, -> { where(resolved_at: nil) }

  # ═══════════════════════════════════════════════════════════════════════════
  # STATUS TRANSITIONS
  # ═══════════════════════════════════════════════════════════════════════════

  def investigate!
    update!(status: 'investigating')
  end

  def resolve!(notes: nil, actions: [])
    update!(
      status: 'resolved',
      resolved_at: Time.current,
      resolution_notes: notes,
      resolution_actions: actions
    )
  end

  def ignore!(reason: nil)
    update!(
      status: 'ignored',
      resolved_at: Time.current,
      resolution_notes: reason
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # STATUS HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  def detected?
    status == 'detected'
  end

  def investigating?
    status == 'investigating'
  end

  def resolved?
    status == 'resolved'
  end

  def active?
    %w[detected investigating].include?(status)
  end

  def critical?
    severity == 'critical'
  end

  def requires_immediate_action?
    critical? && active?
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TARGET HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  def target
    return nil unless target_type.present? && target_id.present?
    target_type.constantize.find_by(id: target_id)
  end

  def target=(record)
    if record.nil?
      self.target_type = nil
      self.target_id = nil
    else
      self.target_type = record.class.name
      self.target_id = record.id
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GOAL CREATION
  # ═══════════════════════════════════════════════════════════════════════════

  def create_remediation_goal!
    return triggered_goal if triggered_goal.present?
    
    goal = AgentGoal.create!(
      entity: entity,
      agent_plugin: target.is_a?(AgentPlugin) ? target : nil,
      goal_type: 'maintenance',
      title: "Resolve: #{title}",
      description: "Automatically generated goal to resolve anomaly: #{description}",
      priority: severity_to_priority,
      source: 'perception',
      suggested_actions: suggested_actions,
      target_type: target_type,
      target_id: target_id,
      metadata: {
        anomaly_id: id,
        anomaly_type: anomaly_type,
        triggering_metrics: triggering_metrics
      }
    )
    
    update!(triggered_goal: goal)
    goal
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SUMMARY
  # ═══════════════════════════════════════════════════════════════════════════

  def summary
    {
      id: id,
      type: anomaly_type,
      severity: severity,
      status: status,
      title: title,
      target: target_type.present? ? "#{target_type}##{target_id}" : nil,
      deviation_percent: deviation_percent,
      created_at: created_at,
      resolved_at: resolved_at
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CLASS METHODS
  # ═══════════════════════════════════════════════════════════════════════════

  class << self
    def create_from_detection(entity:, type:, severity:, title:, target: nil, details: {}, metrics: {})
      create!(
        entity: entity,
        anomaly_type: type,
        severity: severity,
        title: title,
        description: details[:description],
        target_type: target&.class&.name,
        target_id: target&.id,
        details: details,
        triggering_metrics: metrics,
        deviation_percent: details[:deviation_percent],
        suggested_actions: suggest_actions_for_type(type, details)
      )
    end

    def suggest_actions_for_type(type, details)
      case type
      when 'performance_drop'
        ['review_recent_changes', 'trigger_agent_school', 'rollback_prompt_changes']
      when 'error_spike'
        ['analyze_error_logs', 'check_tool_availability', 'verify_integrations']
      when 'resource_anomaly'
        ['check_token_usage', 'review_model_selection', 'optimize_prompts']
      when 'behavior_change'
        ['compare_to_baseline', 'review_training_data', 'check_prompt_changes']
      when 'capacity_issue'
        ['create_specialist_agent', 'load_balance_tasks', 'increase_limits']
      when 'stale_agent'
        ['send_heartbeat', 'restart_agent', 'check_dependencies']
      else
        ['investigate_manually']
      end
    end
  end

  private

  def severity_to_priority
    case severity
    when 'critical' then 95
    when 'high' then 80
    when 'medium' then 60
    when 'low' then 40
    else 50
    end
  end
end


