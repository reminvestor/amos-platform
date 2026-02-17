# frozen_string_literal: true

# PersistObservabilityEventsJob - Background job for persisting observability events
#
# This job handles batch persistence of observability events (workflow executions,
# tool calls, phase executions, etc.) to the database for monitoring and analytics.
#
# Events are collected during workflow execution and batched to minimize database
# writes and improve performance.
#
# Usage:
#   events = [
#     {
#       event_type: "workflow_execution",
#       timestamp: Time.current,
#       data: { entity_id: 1, user_id: 2, duration_ms: 5000 }
#     },
#     {
#       event_type: "tool_execution",
#       timestamp: Time.current,
#       data: { entity_id: 1, tool_name: "create_campaign", duration_ms: 1000 }
#     }
#   ]
#   PersistObservabilityEventsJob.perform_later(events)
class PersistObservabilityEventsJob < ApplicationJob
  queue_as :default

  # Persist a batch of observability events to the database
  #
  # @param events [Array<Hash>] Array of event hashes with keys:
  #   - event_type: Type of event (workflow_execution, tool_execution, etc.)
  #   - timestamp: When the event occurred
  #   - data: Hash of event data (entity_id, user_id, duration_ms, etc.)
  #
  # @example
  #   PersistObservabilityEventsJob.perform_later([
  #     {
  #       event_type: "workflow_execution",
  #       timestamp: Time.current,
  #       data: { entity_id: 1, duration_ms: 5000, status: "success" }
  #     }
  #   ])
  def perform(events)
    return if events.blank?

    # Delegate to ObservabilityEvent.batch_insert for efficient bulk insert
    # This method handles:
    # - Validation of event data
    # - Extracting common fields (entity_id, user_id, etc.) from data hash
    # - Bulk insert with proper error handling
    # - Logging of any failures
    ObservabilityEvent.batch_insert(events)

    Rails.logger.info(
      "[ObservabilityEvents] Persisted batch of #{events.count} events"
    )
  rescue => e
    # Log error but don't fail the job - observability is important but not critical
    # We don't want to block workflow execution if event persistence fails
    Rails.logger.error(
      "[ObservabilityEvents] Failed to persist batch: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    )

    # Optionally: Send alert to monitoring system
    # ErrorTracker.notify(e, context: { event_count: events&.count })
  end
end
