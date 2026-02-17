# frozen_string_literal: true

# ObservabilityEvent - Tracks workflow and system events for monitoring and analytics
#
# This model stores events from:
# - Workflow executions (start, complete, error)
# - Tool executions (tool calls and their results)
# - Phase executions (gather context, execute goal, validate)
# - System events (errors, performance metrics)
#
# Events are batch-inserted for performance via PersistObservabilityEventsJob
#
# Schema:
# - event_type: Type of event (workflow_execution, tool_execution, etc.)
# - entity_id: Which tenant/organization
# - user_id: Which user triggered the event
# - resource_type/resource_id: Polymorphic association to related resource
# - metadata: JSONB with event-specific data
# - duration_ms: How long the operation took
# - status: success, failure, pending, etc.
# - error_message: Error details if status is failure
# - created_at: When the event occurred
class ObservabilityEvent < ApplicationRecord
  # Associations
  belongs_to :entity, optional: true
  belongs_to :user, optional: true
  belongs_to :resource, polymorphic: true, optional: true

  # Validations
  validates :event_type, presence: true

  # Scopes
  scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :by_type, ->(type) { where(event_type: type) }
  scope :successful, -> { where(status: 'success') }
  scope :failed, -> { where(status: 'failure') }
  scope :recent, -> { order(created_at: :desc) }
  scope :this_week, -> { where('created_at >= ?', 1.week.ago) }

  # Class Methods

  # Batch insert multiple events efficiently
  #
  # @param events [Array<Hash>] Array of event hashes with keys:
  #   - event_type: Type of event (required)
  #   - timestamp: When the event occurred (defaults to Time.current)
  #   - data: Hash containing entity_id, user_id, duration_ms, status, etc.
  #
  # @example
  #   ObservabilityEvent.batch_insert([
  #     {
  #       event_type: "workflow_execution",
  #       timestamp: Time.current,
  #       data: { entity_id: 1, user_id: 2, duration_ms: 5000, status: "success" }
  #     },
  #     {
  #       event_type: "tool_execution",
  #       timestamp: Time.current,
  #       data: { entity_id: 1, duration_ms: 1000, status: "success" }
  #     }
  #   ])
  def self.batch_insert(events)
    return if events.blank?

    # Transform events into database records
    records = events.map do |event|
      data = event[:data] || {}
      timestamp = event[:timestamp] || Time.current

      {
        event_type: event[:event_type],
        entity_id: data[:entity_id],
        user_id: data[:user_id],
        resource_type: data[:resource_type],
        resource_id: data[:resource_id],
        metadata: data[:metadata] || data,
        duration_ms: data[:duration_ms],
        status: data[:status],
        error_message: data[:error_message],
        created_at: timestamp,
        updated_at: timestamp
      }
    end

    # Bulk insert using Rails 6+ insert_all
    insert_all(records, returning: false)

    Rails.logger.debug(
      "[ObservabilityEvent] Batch inserted #{records.count} events"
    )
  rescue => e
    # Log error but don't raise - observability shouldn't break workflows
    Rails.logger.error(
      "[ObservabilityEvent] Batch insert failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    )
  end

  # Get event counts by type
  def self.counts_by_type
    group(:event_type).count
  end

  # Get average duration by event type
  def self.average_duration_by_type
    where.not(duration_ms: nil)
      .group(:event_type)
      .average(:duration_ms)
  end

  # Get failure rate by event type
  def self.failure_rate_by_type
    total_by_type = group(:event_type).count
    failures_by_type = where(status: 'failure').group(:event_type).count

    total_by_type.transform_values do |total|
      failures = failures_by_type[total_by_type.key(total)] || 0
      failures.to_f / total * 100
    end
  end
end
