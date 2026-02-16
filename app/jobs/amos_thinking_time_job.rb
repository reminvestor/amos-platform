# frozen_string_literal: true

# AmosThinkingTimeJob - AMOS's autonomous cognitive session
#
# This job orchestrates AMOS's "thinking time" — periods where AMOS
# autonomously reflects on the platform state and takes action.
#
# Two modes:
#   1. AUTONOMOUS (default) - Attention-driven. AMOS perceives signals,
#      decides what matters most, and acts. This is the "brain behind the brain."
#   2. LEGACY - Structured bounty generation using the original
#      AmosThinkingService pipeline. Kept as a fallback.
#
# The autonomous loop:
#   PERCEIVE → ATTEND → THINK → ACT → REFLECT
#
# Inspired by OpenClaw's agent loop concept, extended with working memory,
# attention allocation, and meta-cognition.
#
class AmosThinkingTimeJob < ApplicationJob
  queue_as :living_platform

  # Run for all entities, or a specific one
  # mode: 'autonomous' (default) or 'legacy'
  def perform(entity_id: nil, mode: 'autonomous')
    entities = if entity_id
      [Entity.find(entity_id)]
    else
      Entity.active
    end

    entities.each do |entity|
      run_thinking_session(entity, mode: mode)
    rescue => e
      Rails.logger.error "[AMOS_THINKING] Failed for entity #{entity.id}: #{e.message}"
      Rails.logger.error e.backtrace&.first(5)&.join("\n")
      # Continue with other entities
    end
  end

  private

  def run_thinking_session(entity, mode: 'autonomous')
    Rails.logger.info "[AMOS_THINKING] Starting #{mode} session for #{entity.name}"

    if mode == 'autonomous'
      run_autonomous_session(entity)
    else
      run_legacy_session(entity)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # AUTONOMOUS MODE - Attention-driven cognitive loop
  # ═══════════════════════════════════════════════════════════════════════════

  def run_autonomous_session(entity)
    loop_service = AmosAutonomousLoop.new(entity)
    result = loop_service.run_session!

    Rails.logger.info "[AMOS_THINKING] Autonomous session for #{entity.name}: " \
                      "focused on #{result[:focus_areas].count} areas, " \
                      "#{result[:tokens_used]} tokens used"

    notify_admins_autonomous(entity, result)
    result
  rescue => e
    Rails.logger.warn "[AMOS_THINKING] Autonomous mode failed for #{entity.name}, falling back to legacy: #{e.message}"
    run_legacy_session(entity) # Graceful fallback
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # LEGACY MODE - Structured bounty generation
  # ═══════════════════════════════════════════════════════════════════════════

  def run_legacy_session(entity)
    service = AmosThinkingService.new(entity)
    result = service.think!

    Rails.logger.info "[AMOS_THINKING] Legacy session for #{entity.name}: " \
                      "#{result[:bounties].count} bounties, " \
                      "#{result[:bounties].sum(&:points)} total points"

    notify_admins_legacy(entity, result) if result[:bounties].any?
    result
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # NOTIFICATIONS
  # ═══════════════════════════════════════════════════════════════════════════

  def notify_admins_autonomous(entity, result)
    return unless defined?(SystemNotification)

    bounties_created = result[:results]&.sum { |r| r[:bounties_created] || 0 } || 0
    summary = result[:meta]&.dig(:session_summary) || "Autonomous thinking session completed"

    SystemNotification.create!(
      entity: entity,
      notification_type: 'amos_thinking_complete',
      title: "AMOS autonomous session: #{result[:focus_areas]&.join(', ')}",
      message: summary,
      metadata: {
        session_id: result[:session]&.id,
        mode: 'autonomous',
        focus_areas: result[:focus_areas],
        bounties_created: bounties_created,
        tokens_used: result[:tokens_used],
        active_thoughts: result[:meta]&.dig(:active_thoughts),
        blind_spots: result[:meta]&.dig(:blind_spots)
      }
    )
  rescue => e
    Rails.logger.warn "[AMOS_THINKING] Failed to notify admins: #{e.message}"
  end

  def notify_admins_legacy(entity, result)
    return unless defined?(SystemNotification)

    SystemNotification.create!(
      entity: entity,
      notification_type: 'amos_thinking_complete',
      title: "AMOS created #{result[:bounties].count} new bounties",
      message: result[:reflection][:reflection_summary],
      metadata: {
        session_id: result[:session].id,
        mode: 'legacy',
        bounty_count: result[:bounties].count,
        total_points: result[:bounties].sum(&:points)
      }
    )
  rescue => e
    Rails.logger.warn "[AMOS_THINKING] Failed to notify admins: #{e.message}"
  end
end
