class ObservabilityEvent < ApplicationRecord
  belongs_to :entity, optional: true
  belongs_to :user, optional: true

  validates :event_type, presence: true

  scope :by_type, ->(type) { where(event_type: type) }
  scope :recent, ->(limit = 100) { order(created_at: :desc).limit(limit) }
  scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }
  scope :in_period, ->(start_date, end_date) { where(created_at: start_date..end_date) }

  # Batch insert events from the service buffer
  def self.batch_insert(events)
    return if events.empty?

    records = events.map do |event|
      {
        event_type: event[:event_type],
        entity_id: event.dig(:data, :entity_id),
        user_id: event.dig(:data, :user_id),
        resource_type: event.dig(:data, :resource_type) || "ObservabilityEvent",
        resource_id: event.dig(:data, :task_session_id) || event.dig(:data, :workflow_execution_id),
        metadata: event[:data] || {},
        duration_ms: event.dig(:data, :duration_ms),
        status: event.dig(:data, :success) == false ? "error" : "success",
        error_message: event.dig(:data, :error),
        created_at: event[:timestamp] || Time.current,
        updated_at: Time.current
      }
    end

    insert_all(records)
  rescue => e
    Rails.logger.error "[ObservabilityEvent] Batch insert failed: #{e.message}"
  end
end
