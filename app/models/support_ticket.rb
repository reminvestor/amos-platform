# frozen_string_literal: true

# SupportTicket - Entry point for all issues in the Platform Evolution Engine
#
# Tickets can be created by:
# 1. Users reporting issues (via chat or admin UI)
# 2. AMOS detecting problems (errors, performance issues)
# 3. Log Monitor catching exceptions
# 4. Scheduled health scans
# 5. Agent execution failures
#
class SupportTicket < ApplicationRecord
  belongs_to :entity
  belongs_to :user, optional: true
  belongs_to :scout_conversation, optional: true

  has_many :debug_sessions, dependent: :destroy
  has_many :code_fixes, dependent: :destroy
  has_many :pull_request_submissions, dependent: :destroy
  has_many :error_log_entries, dependent: :nullify
  has_one :bounty, dependent: :nullify

  # Sources
  SOURCES = %w[
    user_reported
    amos_detected
    log_monitor
    scheduled_scan
    agent_failure
  ].freeze

  # Statuses
  STATUSES = %w[
    open
    investigating
    debugging
    fixing
    testing
    pr_submitted
    pr_approved
    resolved
    closed
    wont_fix
  ].freeze

  # Priorities
  PRIORITIES = %w[low medium high critical].freeze

  # Categories
  CATEGORIES = %w[
    bug
    performance
    feature_request
    security
    data_issue
    agent_error
    integration_error
    ui_issue
    documentation
  ].freeze

  validates :ticket_number, presence: true, uniqueness: true
  validates :title, presence: true
  validates :source, inclusion: { in: SOURCES }
  validates :status, inclusion: { in: STATUSES }
  validates :priority, inclusion: { in: PRIORITIES }

  before_validation :generate_ticket_number, on: :create

  scope :open_tickets, -> { where(status: %w[open investigating debugging fixing testing]) }
  scope :awaiting_pr, -> { where(status: %w[pr_submitted pr_approved]) }
  scope :resolved, -> { where(status: %w[resolved closed]) }
  scope :critical, -> { where(priority: 'critical') }
  scope :high_priority, -> { where(priority: %w[high critical]) }
  scope :from_logs, -> { where(source: 'log_monitor') }
  scope :from_users, -> { where(source: 'user_reported') }
  scope :recent, -> { order(created_at: :desc) }
  scope :bugs, -> { where.not(category: 'feature_request') }
  scope :feature_requests, -> { where(category: 'feature_request') }
  scope :awaiting_approval, -> { where(category: 'feature_request', admin_approved: false) }
  scope :approved_features, -> { where(category: 'feature_request', admin_approved: true) }

  # ═══════════════════════════════════════════════════════════════════════════
  # CREATION HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  # Create a ticket from a user report (via AMOS chat)
  def self.create_from_user_report!(entity:, user:, title:, description:, conversation: nil)
    create!(
      entity: entity,
      user: user,
      scout_conversation: conversation,
      title: title,
      description: description,
      source: 'user_reported',
      priority: 'medium',
      category: 'bug'
    )
  end

  # Create a ticket from a log error
  def self.create_from_error!(entity:, error_class:, error_message:, stack_trace:, context: {})
    signature = generate_error_signature(error_class, error_message, stack_trace)

    # Check for existing ticket with same signature
    existing = where(entity: entity, error_signature: signature, status: open_tickets.pluck(:status)).first
    if existing
      existing.increment!(:debug_session_count)
      return existing
    end

    create!(
      entity: entity,
      title: "#{error_class}: #{error_message.truncate(100)}",
      description: "Automatically detected error from logs",
      source: 'log_monitor',
      priority: determine_priority_from_error(error_class),
      category: 'bug',
      error_class: error_class,
      error_message: error_message,
      stack_trace: stack_trace,
      error_signature: signature,
      error_context: context
    )
  end

  # Create a ticket from agent failure
  def self.create_from_agent_failure!(entity:, agent_plugin:, execution:, error_message:)
    create!(
      entity: entity,
      title: "Agent '#{agent_plugin.name}' execution failed",
      description: "Agent execution #{execution.id} failed with: #{error_message}",
      source: 'agent_failure',
      priority: 'medium',
      category: 'agent_error',
      error_message: error_message,
      error_context: {
        agent_plugin_id: agent_plugin.id,
        agent_name: agent_plugin.name,
        execution_id: execution.id,
        input_context: execution.input_context
      }
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # STATUS TRANSITIONS
  # ═══════════════════════════════════════════════════════════════════════════

  def start_investigation!
    update!(status: 'investigating', time_to_first_response_minutes: minutes_since_creation)
  end

  def start_debugging!
    update!(status: 'debugging')
  end

  def start_fixing!
    update!(status: 'fixing')
  end

  def start_testing!
    update!(status: 'testing')
  end

  def pr_submitted!(pr_url)
    update!(status: 'pr_submitted', metadata: metadata.merge(pr_url: pr_url))
  end

  def pr_approved!
    update!(status: 'pr_approved')
  end

  def resolve!(notes: nil, resolved_by: nil)
    update!(
      status: 'resolved',
      resolved_at: Time.current,
      resolved_by: resolved_by,
      resolution_notes: notes,
      time_to_resolution_minutes: minutes_since_creation
    )
  end

  def close!(notes: nil)
    update!(status: 'closed', resolution_notes: notes)
  end

  def mark_wont_fix!(reason:)
    update!(status: 'wont_fix', resolution_notes: reason)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FEATURE REQUEST APPROVAL
  # ═══════════════════════════════════════════════════════════════════════════

  def is_feature_request?
    category == 'feature_request'
  end

  def is_bug?
    !is_feature_request?
  end

  # Feature requests need admin approval before work begins
  def needs_admin_approval?
    is_feature_request? && !admin_approved?
  end

  # Bugs can be auto-processed, features need approval
  def can_auto_process?
    is_bug? || admin_approved?
  end

  def approve_feature!(approved_by:)
    return false unless is_feature_request?
    
    update!(
      admin_approved: true,
      admin_approved_by_id: approved_by.id,
      admin_approved_at: Time.current
    )
  end

  def reject_feature!(reason:, rejected_by:)
    return false unless is_feature_request?
    
    update!(
      status: 'wont_fix',
      resolution_notes: "Feature request rejected: #{reason}",
      admin_approved: false
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # DEBUG SESSION MANAGEMENT
  # ═══════════════════════════════════════════════════════════════════════════

  def create_debug_session!(user: nil)
    increment!(:debug_session_count)
    debug_sessions.create!(
      entity: entity,
      user: user,
      started_at: Time.current
    )
  end

  def active_debug_session
    debug_sessions.where(status: %w[gathering_info analyzing reproducing proposing_fix]).order(created_at: :desc).first
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # QUERIES
  # ═══════════════════════════════════════════════════════════════════════════

  def is_open?
    %w[open investigating debugging fixing testing].include?(status)
  end

  def is_critical?
    priority == 'critical'
  end

  def has_pending_pr?
    %w[pr_submitted pr_approved].include?(status)
  end

  def to_context
    {
      ticket_number: ticket_number,
      title: title,
      description: description,
      status: status,
      priority: priority,
      category: category,
      error_class: error_class,
      error_message: error_message,
      stack_trace: stack_trace&.first(2000),
      created_at: created_at,
      source: source
    }
  end

  private

  def generate_ticket_number
    return if ticket_number.present?

    # Generate AMOS-XXXX format
    last_ticket = SupportTicket.order(id: :desc).first
    last_num = last_ticket&.ticket_number&.gsub('AMOS-', '')&.to_i || 0
    self.ticket_number = "AMOS-#{(last_num + 1).to_s.rjust(5, '0')}"
  end

  def minutes_since_creation
    ((Time.current - created_at) / 60).round
  end

  def self.generate_error_signature(error_class, error_message, stack_trace)
    # Create a signature from the first meaningful stack frame
    first_app_frame = stack_trace&.lines&.find { |l| l.include?('app/') || l.include?('lib/') }
    content = "#{error_class}|#{error_message&.gsub(/\d+/, 'N')}|#{first_app_frame}"
    Digest::SHA256.hexdigest(content)[0..16]
  end

  def self.determine_priority_from_error(error_class)
    case error_class
    when /Security/, /Auth/, /Unauthorized/, /Forbidden/
      'critical'
    when /Database/, /Connection/, /Timeout/
      'high'
    when /NotFound/, /Validation/, /Invalid/
      'medium'
    else
      'medium'
    end
  end
end

