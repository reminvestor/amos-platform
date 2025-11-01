class PipelineInteraction < ApplicationRecord
  # Relationships
  belongs_to :pipeline_execution
  belongs_to :user, optional: true

  # Validations
  validates :interaction_type, presence: true, inclusion: { in: %w[clarification approval rejection] }
  validates :channel, presence: true, inclusion: { in: %w[slack teams email] }
  validates :question, presence: true
  validates :asked_at, presence: true

  # Enums
  enum :status, {
    pending: 0,
    answered: 1,
    timeout: 2
  }, prefix: true

  # Scopes
  scope :pending, -> { where(status: :pending) }
  scope :answered, -> { where(status: :answered) }
  scope :timed_out, -> { where(status: :timeout) }
  scope :clarifications, -> { where(interaction_type: 'clarification') }
  scope :approvals, -> { where(interaction_type: 'approval') }
  scope :by_channel, ->(channel) { where(channel: channel) }
  scope :recent, -> { order(asked_at: :desc) }

  # Callbacks
  after_initialize :set_defaults, if: :new_record?
  after_create :send_notification

  # Answer the interaction
  def answer!(user, response_text)
    update!(
      user: user,
      response: response_text,
      status: :answered,
      answered_at: Time.current
    )

    # Trigger pipeline continuation
    continue_pipeline!
  end

  # Mark as timed out
  def mark_timeout!
    return unless status_pending?

    update!(
      status: :timeout,
      answered_at: Time.current
    )

    # Handle timeout (escalate, retry, or fail)
    handle_timeout!
  end

  # Check if timed out
  def timed_out?
    return false unless timeout_at
    Time.current > timeout_at && status_pending?
  end

  # Calculate response time
  def response_time
    return nil unless answered_at && asked_at
    answered_at - asked_at
  end

  # Human-readable response time
  def response_time_human
    return 'N/A' unless response_time
    seconds = response_time.to_i
    hours = seconds / 3600
    minutes = (seconds % 3600) / 60

    if hours > 0
      "#{hours}h #{minutes}m"
    elsif minutes > 0
      "#{minutes}m"
    else
      "#{seconds}s"
    end
  end

  # Get timeout remaining
  def timeout_remaining
    return nil unless timeout_at && status_pending?
    remaining = timeout_at - Time.current
    remaining > 0 ? remaining : 0
  end

  # Human-readable interaction type
  def type_label
    interaction_type.titleize
  end

  private

  def set_defaults
    self.status ||= :pending
    self.asked_at ||= Time.current

    # Set default timeout based on interaction type
    if timeout_at.blank?
      timeout_duration = case interaction_type
                        when 'clarification' then 2.hours
                        when 'approval' then 4.hours
                        when 'rejection' then 1.hour
                        else 2.hours
                        end
      self.timeout_at = asked_at + timeout_duration
    end
  end

  def send_notification
    # Send notification via configured channel
    notifier = case channel
              when 'slack'
                AiAgents::Notifiers::SlackNotifier.new
              when 'teams'
                AiAgents::Notifiers::TeamsNotifier.new
              when 'email'
                AiAgents::Notifiers::EmailNotifier.new
              else
                Rails.logger.error "Unknown notification channel: #{channel}"
                return
              end

    notifier.send_interaction_notification(self)
  rescue => e
    Rails.logger.error "Failed to send interaction notification: #{e.message}"
  end

  def continue_pipeline!
    # Resume pipeline execution after interaction is answered
    ProcessPipelineJob.perform_later(pipeline_execution_id)
  end

  def handle_timeout!
    # Log timeout
    Rails.logger.warn "Interaction #{id} timed out for pipeline #{pipeline_execution_id}"

    # Escalate or fail pipeline based on interaction type
    case interaction_type
    when 'clarification'
      # Block pipeline and escalate
      pipeline_execution.transition_to!(:blocked, event: 'interaction.timeout', metadata: { interaction_id: id })
    when 'approval'
      # Block production deployment
      pipeline_execution.transition_to!(:blocked, event: 'approval.timeout', metadata: { interaction_id: id })
    else
      # Generic blocking
      pipeline_execution.update!(status: :blocked)
    end
  end
end
