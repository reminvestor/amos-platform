class PipelineEvent < ApplicationRecord
  # Relationships
  belongs_to :pipeline_execution

  # Validations
  validates :event_type, presence: true
  validates :source, presence: true, inclusion: { in: %w[jira azure_devops github azure_repos agent human system] }

  # Event types from spec
  EVENT_TYPES = %w[
    ticket.intake
    ticket.updated
    ticket.clarified
    ticket.needs_clarification
    plan.ready
    pr.opened
    pr.approved
    pr.needs_changes
    pr.merged
    tests.passed
    tests.failed
    cua.dev_passed
    cua.staging_passed
    cua.failed
    dev.merge
    staging.promoted
    prod.promoted
    execution.failed
    rollback.triggered
    human.approved
    human.rejected
  ].freeze

  validates :event_type, inclusion: { in: EVENT_TYPES }

  # Scopes
  scope :unprocessed, -> { where(processed: false) }
  scope :processed, -> { where(processed: true) }
  scope :by_type, ->(type) { where(event_type: type) }
  scope :by_source, ->(source) { where(source: source) }
  scope :recent, -> { order(created_at: :desc) }
  scope :chronological, -> { order(created_at: :asc) }

  # Callbacks
  after_initialize :set_defaults, if: :new_record?
  after_create :trigger_event_handlers

  # Mark as processed
  def mark_processed!
    update!(processed: true)
  end

  # Get event category
  def category
    event_type.split('.').first
  end

  # Get event action
  def action
    event_type.split('.').last
  end

  # Human-readable event name
  def event_name
    event_type.split('.').join(' ').titleize
  end

  private

  def set_defaults
    self.processed ||= false
    self.payload ||= {}
  end

  def trigger_event_handlers
    # Trigger async event processing
    # This will be handled by ProcessPipelineJob which listens for events
    Rails.logger.info "Pipeline event created: #{event_type} for execution #{pipeline_execution_id}"
  end
end
