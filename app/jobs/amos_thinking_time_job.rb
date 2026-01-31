# frozen_string_literal: true

# AmosThinkingTimeJob - AMOS's nightly reflection and bounty generation
#
# Runs nightly (or on-demand) to:
# 1. Analyze platform state
# 2. Reflect on improvements
# 3. Generate bounties for contributors
#
# Inspired by OpenClaw's agent loop concept.
#
class AmosThinkingTimeJob < ApplicationJob
  queue_as :low

  # Run for all entities, or a specific one
  def perform(entity_id: nil)
    entities = if entity_id
      [Entity.find(entity_id)]
    else
      Entity.active
    end

    entities.each do |entity|
      run_thinking_session(entity)
    rescue => e
      Rails.logger.error "[AMOS_THINKING] Failed for entity #{entity.id}: #{e.message}"
      # Continue with other entities
    end
  end

  private

  def run_thinking_session(entity)
    Rails.logger.info "[AMOS_THINKING] Starting thinking session for #{entity.name}"

    service = AmosThinkingService.new(entity)
    result = service.think!

    Rails.logger.info "[AMOS_THINKING] Completed for #{entity.name}: " \
                      "#{result[:bounties].count} bounties, " \
                      "#{result[:bounties].sum(&:points)} total points"

    # Optionally notify admins
    notify_admins(entity, result) if result[:bounties].any?

    result
  end

  def notify_admins(entity, result)
    # Send notification about new bounties
    # This could be email, Slack, in-app notification, etc.
    return unless defined?(SystemNotification)

    SystemNotification.create!(
      entity: entity,
      notification_type: 'amos_thinking_complete',
      title: "AMOS created #{result[:bounties].count} new bounties",
      message: result[:reflection][:reflection_summary],
      metadata: {
        session_id: result[:session].id,
        bounty_count: result[:bounties].count,
        total_points: result[:bounties].sum(&:points)
      }
    )
  rescue => e
    Rails.logger.warn "[AMOS_THINKING] Failed to notify admins: #{e.message}"
  end
end
