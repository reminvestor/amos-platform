# frozen_string_literal: true

# PlatformEvolutionTicket - Tracks PLATFORM-LEVEL improvement opportunities
#
# IMPORTANT DISTINCTION:
# - User wants a tool/agent/workflow → Amos builds it via Factory systems (NOT a ticket)
# - Platform needs code changes → That's a ticket for the external dev process
#
# These tickets are for things that require changes to the Amos codebase itself,
# NOT things users can build. A separate AI application picks up these tickets
# and works on the underlying platform code.
#
# Ticket types:
# - model_upgrade: Need to support a new AI model
# - ui_improvement: Chat interface needs enhancement
# - performance_fix: System performance issue
# - core_bug: Bug in the platform code
# - integration_api: External API changed, need to update integration
# - prompt_engineering: System prompts need refinement (not user loadouts)
# - infrastructure: Deployment, scaling, or ops changes
#
class PlatformEvolutionTicket < ApplicationRecord
  belongs_to :entity
  belongs_to :assigned_to, polymorphic: true, optional: true
  belongs_to :created_by, polymorphic: true, optional: true
  belongs_to :completed_by, polymorphic: true, optional: true

  # Platform-level ticket types (NOT user-buildable features)
  TICKET_TYPES = %w[
    model_upgrade
    ui_improvement
    performance_fix
    core_bug
    integration_api
    prompt_engineering
    infrastructure
    security_patch
    dependency_update
  ].freeze

  STATUSES = %w[open in_progress completed rejected blocked deferred].freeze
  PRIORITIES = %w[low medium high critical].freeze
  SOURCES = %w[auto_detected metric_alert admin_created ai_suggested user_feedback].freeze
  TARGET_AREAS = %w[models ui performance core integrations prompts infrastructure security].freeze

  validates :ticket_type, presence: true, inclusion: { in: TICKET_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :priority, presence: true, inclusion: { in: PRIORITIES }
  validates :title, presence: true

  scope :open_tickets, -> { where(status: 'open') }
  scope :in_progress, -> { where(status: 'in_progress') }
  scope :completed, -> { where(status: 'completed') }
  scope :by_priority, -> { order(Arel.sql("CASE priority WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END")) }
  scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }
  scope :unassigned, -> { where(assigned_to: nil) }
  scope :actionable, -> { open_tickets.unassigned.by_priority }

  # ═══════════════════════════════════════════════════════════════
  # LIFECYCLE METHODS
  # ═══════════════════════════════════════════════════════════════

  def claim!(worker)
    return false unless status == 'open'
    update!(status: 'in_progress', assigned_to: worker, started_at: Time.current)
  end

  def complete!(worker, implementation_details: {})
    update!(
      status: 'completed',
      completed_by: worker,
      completed_at: Time.current,
      implementation_details: implementation_details,
      actual_hours: started_at ? ((Time.current - started_at) / 1.hour).round : nil
    )
  end

  def reject!(reason:)
    update!(status: 'rejected', implementation_details: { rejection_reason: reason })
  end

  def block!(reason:)
    update!(status: 'blocked', implementation_details: implementation_details.merge(blocked_reason: reason))
  end

  # ═══════════════════════════════════════════════════════════════
  # AUTO-GENERATION METHODS
  # ═══════════════════════════════════════════════════════════════

  # Create tickets for PLATFORM-LEVEL issues only
  # User-buildable features (tools, loadouts) should NOT create tickets
  def self.create_from_pattern(entity:, pattern_type:, evidence:, created_by: nil)
    ticket_config = case pattern_type
    when :model_performance_degradation
      {
        ticket_type: 'model_upgrade',
        title: "Model performance degrading: #{evidence[:model_name]}",
        description: "Model #{evidence[:model_name]} showing degraded performance. Consider upgrading or switching.",
        priority: evidence[:degradation_percent].to_f > 20 ? 'high' : 'medium',
        target_area: 'models',
        target_slug: evidence[:model_name]
      }
    when :high_latency
      {
        ticket_type: 'performance_fix',
        title: "High latency detected: #{evidence[:area]}",
        description: "Average response time: #{evidence[:avg_ms]}ms (threshold: #{evidence[:threshold_ms]}ms)",
        priority: evidence[:avg_ms].to_i > 10000 ? 'critical' : 'high',
        target_area: 'performance',
        target_slug: evidence[:area]
      }
    when :api_errors
      {
        ticket_type: 'integration_api',
        title: "Integration API errors: #{evidence[:integration_name]}",
        description: "Integration #{evidence[:integration_name]} returning errors: #{evidence[:error_summary]}",
        priority: evidence[:error_rate].to_f > 50 ? 'critical' : 'high',
        target_area: 'integrations',
        target_slug: evidence[:integration_name]
      }
    when :system_prompt_ineffective
      {
        ticket_type: 'prompt_engineering',
        title: "System prompt refinement needed",
        description: "Amos core prompts may need adjustment based on pattern: #{evidence[:pattern]}",
        priority: 'medium',
        target_area: 'prompts',
        target_slug: 'amos_identity'
      }
    when :security_vulnerability
      {
        ticket_type: 'security_patch',
        title: "Security issue detected: #{evidence[:issue_type]}",
        description: evidence[:description],
        priority: 'critical',
        target_area: 'security',
        target_slug: evidence[:component]
      }
    when :dependency_outdated
      {
        ticket_type: 'dependency_update',
        title: "Dependency update: #{evidence[:gem_name]}",
        description: "#{evidence[:gem_name]} has a new version: #{evidence[:new_version]} (current: #{evidence[:current_version]})",
        priority: evidence[:security_fix] ? 'high' : 'low',
        target_area: 'infrastructure',
        target_slug: evidence[:gem_name]
      }
    when :ui_feedback
      {
        ticket_type: 'ui_improvement',
        title: "UI improvement request: #{evidence[:area]}",
        description: evidence[:feedback],
        priority: 'medium',
        target_area: 'ui',
        target_slug: evidence[:area]
      }
    else
      {
        ticket_type: 'core_bug',
        title: "Platform issue: #{pattern_type}",
        description: "Auto-detected platform pattern: #{pattern_type}\n\nEvidence: #{evidence.to_json}",
        priority: 'medium',
        target_area: 'core'
      }
    end

    # Check for duplicates
    existing = where(entity: entity, target_slug: ticket_config[:target_slug], status: %w[open in_progress])
                 .where(ticket_type: ticket_config[:ticket_type])
                 .first

    if existing
      # Update evidence with new data
      existing.update!(evidence: existing.evidence.merge(evidence.stringify_keys))
      existing
    else
      create!(
        entity: entity,
        source: 'auto_detected',
        evidence: evidence,
        created_by: created_by,
        **ticket_config
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # ANALYTICS
  # ═══════════════════════════════════════════════════════════════

  def self.stats(entity_id:)
    tickets = for_entity(entity_id)
    {
      total: tickets.count,
      open: tickets.open_tickets.count,
      in_progress: tickets.in_progress.count,
      completed: tickets.completed.count,
      by_type: tickets.group(:ticket_type).count,
      by_priority: tickets.group(:priority).count,
      avg_completion_hours: tickets.completed.average(:actual_hours)&.round(1)
    }
  end
end
