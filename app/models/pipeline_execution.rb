class PipelineExecution < ApplicationRecord
  # Multi-tenant scoping
  belongs_to :entity

  # Relationships
  belongs_to :mcp_connection
  belongs_to :git_connection, class_name: 'McpConnection', optional: true
  has_many :agent_executions, dependent: :destroy
  has_many :pipeline_artifacts, dependent: :destroy
  has_many :pipeline_events, dependent: :destroy
  has_many :pipeline_interactions, dependent: :destroy

  # Validations
  validates :ticket_id, presence: true
  validates :ticket_id, uniqueness: { scope: [:entity_id, :mcp_connection_id],
                                      message: 'pipeline already exists for this ticket' }
  validates :ticket_system, presence: true, inclusion: { in: %w[jira azure_devops] }
  validates :ticket_title, presence: true
  validates :status, presence: true
  validates :priority, presence: true

  # Enums for status (14 states from spec)
  enum :status, {
    new: 0,
    clarifying: 1,
    planning: 2,
    implementing: 3,
    review: 4,
    testing: 5,
    dev: 6,
    staging: 7,
    awaiting_prod_approval: 8,
    prod: 9,
    done: 10,
    failed: 11,
    rolled_back: 12,
    blocked: 13
  }, prefix: true

  # Enums for priority
  enum :priority, {
    critical: 0,
    high: 1,
    medium: 2,
    low: 3
  }, prefix: true

  # Scopes
  scope :active, -> { where.not(status: [:done, :failed, :rolled_back]) }
  scope :in_progress, -> { where(status: [:clarifying, :planning, :implementing, :review, :testing]) }
  scope :awaiting_deployment, -> { where(status: [:dev, :staging, :awaiting_prod_approval]) }
  scope :completed_successfully, -> { where(status: :done) }
  scope :failed_executions, -> { where(status: :failed) }
  scope :by_priority, -> { order(priority: :asc, created_at: :desc) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  after_initialize :set_defaults, if: :new_record?
  before_save :update_state_history, if: :will_save_change_to_status?

  # State machine transitions
  def can_transition_to?(new_state)
    Pipeline::StateMachine.can_transition?(self.status, new_state.to_s)
  end

  def transition_to!(new_state, event: nil, metadata: {})
    new_state_str = new_state.to_s

    unless can_transition_to?(new_state)
      raise "Invalid state transition from #{status} to #{new_state_str}"
    end

    update!(
      status: new_state_str,
      state_changed_at: Time.current
    )

    # Record event if provided
    if event
      pipeline_events.create!(
        event_type: event,
        source: 'system',
        payload: metadata
      )
    end

    # Notify state change
    notify_state_change(new_state_str, metadata)
  end

  # Add tokens and cost
  def add_tokens(tokens, cost)
    update!(
      total_tokens_used: (total_tokens_used || 0) + tokens,
      total_cost: (total_cost || 0) + cost
    )
  end

  # Get latest agent execution for a specific agent
  def latest_agent_execution(agent_id)
    agent_executions.where(agent_id: agent_id).order(created_at: :desc).first
  end

  # Get all artifacts of a specific type
  def artifacts_of_type(artifact_type)
    pipeline_artifacts.where(artifact_type: artifact_type)
  end

  # Check if execution is complete
  def complete?
    %w[done failed rolled_back].include?(status)
  end

  # Check if execution is in a terminal state
  def terminal_state?
    complete?
  end

  # Calculate duration
  def duration
    return nil unless started_at
    end_time = completed_at || Time.current
    end_time - started_at
  end

  # Format duration as human-readable
  def duration_human
    return 'N/A' unless duration
    seconds = duration.to_i
    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    secs = seconds % 60

    if hours > 0
      "#{hours}h #{minutes}m"
    elsif minutes > 0
      "#{minutes}m #{secs}s"
    else
      "#{secs}s"
    end
  end

  # Get cost in dollars
  def cost_dollars
    return '$0.00' unless total_cost
    "$#{total_cost.round(2)}"
  end

  # Get pending interactions
  def pending_interactions
    pipeline_interactions.where(status: :pending)
  end

  # Check if blocked by human interaction
  def blocked_by_interaction?
    pending_interactions.any?
  end

  # Start execution
  def start!
    update!(started_at: Time.current) unless started_at
  end

  # Complete execution
  def complete!(success: true)
    update!(
      completed_at: Time.current,
      status: success ? :done : :failed
    )
  end

  # Fail execution with error
  def fail!(error_message)
    transition_to!(:failed, event: 'execution.failed', metadata: { error: error_message })
    update!(completed_at: Time.current)
  end

  # Retry failed execution
  def retry!
    raise "Can only retry failed executions" unless status_failed?

    # Reset state
    update!(
      status: :new,
      completed_at: nil,
      state_changed_at: Time.current
    )

    # Clear failed agent executions
    agent_executions.where(status: :failed).destroy_all

    # Enqueue processing job
    ProcessPipelineJob.perform_later(id)
  end

  private

  def set_defaults
    self.status ||= :new
    self.priority ||= :medium
    self.ticket_metadata ||= {}
    self.state_history ||= []
    self.total_tokens_used ||= 0
    self.total_cost ||= 0.0
  end

  def update_state_history
    return unless will_save_change_to_status?

    old_status = status_was || 'none'
    new_status = status

    history_entry = {
      from: old_status,
      to: new_status,
      timestamp: Time.current.iso8601,
      duration_seconds: state_changed_at ? (Time.current - state_changed_at).to_i : nil
    }

    self.state_history ||= []
    self.state_history << history_entry
  end

  def notify_state_change(new_state, metadata)
    # Send notifications via configured channels (Slack, Teams, Email)
    # This will be implemented by the Notifiers
    Rails.logger.info "Pipeline #{id} transitioned to #{new_state}: #{metadata.inspect}"
  end
end
