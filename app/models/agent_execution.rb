class AgentExecution < ApplicationRecord
  # Relationships
  belongs_to :pipeline_execution
  has_many :pipeline_artifacts, dependent: :nullify

  # Validations
  validates :agent_id, presence: true, inclusion: {
    in: %w[clarifier planner coder reviewer cua_pack release_manager]
  }
  validates :status, presence: true

  # Enums
  enum :status, {
    pending: 0,
    running: 1,
    completed: 2,
    failed: 3
  }, prefix: true

  # Scopes
  scope :successful, -> { where(status: :completed) }
  scope :failures, -> { where(status: :failed) }
  scope :in_progress, -> { where(status: [:pending, :running]) }
  scope :by_agent, ->(agent_id) { where(agent_id: agent_id) }
  scope :recent, -> { order(started_at: :desc) }

  # Callbacks
  after_initialize :set_defaults, if: :new_record?

  # Start execution
  def start!
    update!(
      status: :running,
      started_at: Time.current
    )
  end

  # Complete successfully
  def complete!(outputs = {})
    update!(
      status: :completed,
      completed_at: Time.current,
      outputs: outputs
    )
  end

  # Fail with error
  def fail!(error_message, error_details = {})
    update!(
      status: :failed,
      completed_at: Time.current,
      error_message: error_message,
      outputs: error_details
    )
  end

  # Add to logs
  def append_log(message)
    self.logs ||= ''
    self.logs += "#{Time.current.iso8601} - #{message}\n"
    save!
  end

  # Record token usage
  def record_tokens(tokens, cost)
    update!(
      tokens_used: (tokens_used || 0) + tokens,
      cost: (self.cost || 0) + cost
    )

    # Also update parent pipeline execution
    pipeline_execution.add_tokens(tokens, cost)
  end

  # Calculate duration
  def duration
    return nil unless started_at
    end_time = completed_at || Time.current
    end_time - started_at
  end

  # Human-readable agent name
  def agent_name
    agent_id.titleize
  end

  # Get workspace directory
  def workspace_dir
    workspace_path || "/tmp/pipeline-#{pipeline_execution_id}/#{agent_id}"
  end

  private

  def set_defaults
    self.status ||= :pending
    self.inputs ||= {}
    self.outputs ||= {}
    self.tokens_used ||= 0
    self.cost ||= 0.0
  end
end
