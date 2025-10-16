class TaskEvent < ApplicationRecord
  belongs_to :task_session

  # Validations
  validates :event_type, presence: true
  validates :sequence_number, uniqueness: { scope: :task_session_id }

  # Scopes
  scope :ordered, -> { order(:sequence_number) }
  scope :by_type, ->(type) { where(event_type: type) }
  scope :recent, -> { order(created_at: :desc) }

  # Event type constants
  EVENT_TYPES = {
    # Workflow events
    session_started: "session_started",
    step_started: "step_started",
    step_completed: "step_completed",
    step_failed: "step_failed",

    # User interaction events
    user_input: "user_input",
    data_collected: "data_collected",
    user_feedback: "user_feedback",

    # Tool events
    tool_called: "tool_called",
    tool_completed: "tool_completed",
    tool_failed: "tool_failed",

    # Artifact events
    artifact_created: "artifact_created",
    artifact_updated: "artifact_updated",

    # AI events
    ai_response: "ai_response",
    mode_detected: "mode_detected"
  }.freeze

  # Helper methods
  def elapsed_time_since_previous
    previous_event = task_session.task_events
      .where("sequence_number < ?", sequence_number)
      .ordered
      .last

    return nil unless previous_event

    created_at - previous_event.created_at
  end

  # Analytics helpers
  def self.average_time_between_types(from_type, to_type, task_session_ids = nil)
    scope = self
    scope = scope.where(task_session_id: task_session_ids) if task_session_ids

    from_events = scope.by_type(from_type).pluck(:task_session_id, :created_at)
    to_events = scope.by_type(to_type).pluck(:task_session_id, :created_at)

    times = []
    from_events.each do |session_id, from_time|
      to_time = to_events.find { |sid, _| sid == session_id }&.last
      next unless to_time && to_time > from_time

      times << (to_time - from_time)
    end

    return nil if times.empty?

    times.sum / times.length
  end
end
