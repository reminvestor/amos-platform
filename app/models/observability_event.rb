class ObservabilityEvent < ApplicationRecord
  belongs_to :entity, optional: true
  belongs_to :user, optional: true

  validates :event_type, presence: true

  scope :by_type, ->(type) { where(event_type: type) }
  scope :recent, ->(limit = 100) { order(created_at: :desc).limit(limit) }
  scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }
  scope :in_period, ->(start_date, end_date) { where(created_at: start_date..end_date) }

  # Batch insert events from the service buffer
  # Note: ActiveJob serializes arguments as JSON, converting symbol keys to strings.
  # We use with_indifferent_access to handle both symbol and string keys.
  def self.batch_insert(events)
    return if events.empty?

    records = events.map do |event|
      event = event.with_indifferent_access if event.respond_to?(:with_indifferent_access)
      data = event[:data]
      data = data.with_indifferent_access if data.respond_to?(:with_indifferent_access)
      {
        event_type: event[:event_type],
        entity_id: data&.dig(:entity_id),
        user_id: data&.dig(:user_id),
        resource_type: data&.dig(:resource_type) || "ObservabilityEvent",
        resource_id: data&.dig(:task_session_id) || data&.dig(:workflow_execution_id),
        metadata: data || {},
        duration_ms: data&.dig(:duration_ms),
        status: data&.dig(:success) == false ? "error" : "success",
        error_message: data&.dig(:error),
        created_at: event[:timestamp] || Time.current,
        updated_at: Time.current
      }
    end

    insert_all(records)
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.error "[ObservabilityEvent] Batch insert failed: #{e.message}"
  end
end
