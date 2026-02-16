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
  include AmosSignalEmitter

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
  before_create :check_for_duplicate
  after_create :emit_ticket_created_signal

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
  # CREATION HELPERS (all paths go through dedup)
  # ═══════════════════════════════════════════════════════════════════════════

  # Create a ticket from a user report (via AMOS chat)
  # Returns existing ticket if a similar one already exists (adds user to affected list)
  def self.create_from_user_report!(entity:, user:, title:, description:, conversation: nil)
    fingerprint = generate_content_fingerprint(title, description)

    # Check for existing similar ticket
    existing = find_similar_open_ticket(entity: entity, fingerprint: fingerprint, title: title)
    if existing
      existing.add_affected_user!(user)
      return existing
    end

    create!(
      entity: entity,
      user: user,
      scout_conversation: conversation,
      title: title,
      description: description,
      source: 'user_reported',
      priority: 'medium',
      category: 'bug',
      content_fingerprint: fingerprint,
      affected_user_ids: user ? [user.id] : [],
      affected_user_count: 1
    )
  end

  # Create a ticket from a log error
  def self.create_from_error!(entity:, error_class:, error_message:, stack_trace:, context: {})
    signature = generate_error_signature(error_class, error_message, stack_trace)

    # Check for existing ticket with same signature
    existing = where(entity: entity, error_signature: signature).open_tickets.first
    if existing
      existing.increment!(:debug_session_count)
      existing.increment!(:affected_user_count)
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
      error_context: context,
      content_fingerprint: signature
    )
  end

  # Create a ticket from agent failure
  def self.create_from_agent_failure!(entity:, agent_plugin:, execution:, error_message:)
    fingerprint = generate_content_fingerprint("Agent #{agent_plugin.name} failed", error_message)

    # Check for existing similar agent failure
    existing = find_similar_open_ticket(entity: entity, fingerprint: fingerprint)
    if existing
      existing.increment!(:affected_user_count)
      # Append this execution to context
      existing_execs = existing.error_context&.dig('execution_ids') || []
      existing.update!(error_context: existing.error_context.merge(
        'execution_ids' => existing_execs + [execution.id],
        'latest_error' => error_message,
        'latest_at' => Time.current.iso8601
      ))
      return existing
    end

    create!(
      entity: entity,
      title: "Agent '#{agent_plugin.name}' execution failed",
      description: "Agent execution #{execution.id} failed with: #{error_message}",
      source: 'agent_failure',
      priority: 'medium',
      category: 'agent_error',
      error_message: error_message,
      content_fingerprint: fingerprint,
      error_context: {
        agent_plugin_id: agent_plugin.id,
        agent_name: agent_plugin.name,
        execution_id: execution.id,
        execution_ids: [execution.id],
        input_context: execution.input_context
      }
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # DEDUP & AFFECTED USERS
  # ═══════════════════════════════════════════════════════════════════════════

  # Add a user to the affected list of an existing ticket
  def add_affected_user!(user)
    return unless user

    current_ids = affected_user_ids || []
    return if current_ids.include?(user.id)

    update!(
      affected_user_ids: current_ids + [user.id],
      affected_user_count: current_ids.length + 1
    )

    # Escalate priority if many users affected
    escalate_by_user_count!

    Rails.logger.info "[SupportTicket] Added user #{user.id} to ticket #{ticket_number} " \
                      "(now #{affected_user_count} affected)"
  end

  # Find a similar open ticket by fingerprint or fuzzy title match
  def self.find_similar_open_ticket(entity:, fingerprint: nil, title: nil)
    # Priority 1: Exact fingerprint match
    if fingerprint.present?
      match = where(entity: entity, content_fingerprint: fingerprint).open_tickets.first
      return match if match
    end

    # Priority 2: Same error_signature
    # (already handled in create_from_error!)

    # Priority 3: Fuzzy title match (for user reports)
    if title.present?
      normalized = normalize_for_comparison(title)
      # Check recent open tickets with similar titles
      where(entity: entity).open_tickets.where('created_at > ?', 30.days.ago).find_each do |ticket|
        ticket_normalized = normalize_for_comparison(ticket.title)
        # Simple word overlap similarity
        if word_similarity(normalized, ticket_normalized) >= 0.7
          return ticket
        end
      end
    end

    nil
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
  # READINESS & BOUNTY ELIGIBILITY
  # ═══════════════════════════════════════════════════════════════════════════

  scope :bounty_eligible, -> { where(bounty_eligible: true) }
  scope :needs_qualification, -> { where(readiness_assessed_at: nil) }
  scope :qualified, -> { where('readiness_score >= ?', TicketQualificationService::BOUNTY_READINESS_THRESHOLD) }

  def bounty_ready?
    bounty_eligible? && readiness_score.to_i >= TicketQualificationService::BOUNTY_READINESS_THRESHOLD
  end

  def qualify!
    TicketQualificationService.qualify!(self)
  end

  def readiness_label
    case readiness_score.to_i
    when 0..30 then 'Insufficient'
    when 31..50 then 'Partial'
    when 51..70 then 'Good'
    when 71..90 then 'Strong'
    when 91..100 then 'Excellent'
    else 'Unassessed'
    end
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

  # ═══════════════════════════════════════════════════════════════════════════
  # DEDUP (before_create)
  # ═══════════════════════════════════════════════════════════════════════════

  def check_for_duplicate
    return if content_fingerprint.blank? && error_signature.blank?

    # Check fingerprint match
    fp = content_fingerprint || error_signature
    existing = self.class.where(entity: entity)
                         .open_tickets
                         .where('content_fingerprint = ? OR error_signature = ?', fp, fp)
                         .where.not(id: id)
                         .first

    if existing
      # Merge into existing: add user, bump count, DON'T create new record
      existing.add_affected_user!(user) if user.present?
      existing.increment!(:affected_user_count) unless user.present?

      Rails.logger.info "[SupportTicket] Dedup: merged into #{existing.ticket_number} " \
                        "(#{existing.affected_user_count} affected)"

      # Halt the create — throw :abort to prevent save
      throw :abort
    end
  end

  # Auto-escalate priority when many users are affected
  def escalate_by_user_count!
    new_priority = case affected_user_count
                   when 5..9 then 'high'
                   when 10.. then 'critical'
                   else nil
                   end

    if new_priority && PRIORITIES.index(new_priority) > PRIORITIES.index(priority)
      update!(priority: new_priority)
      Rails.logger.info "[SupportTicket] Auto-escalated #{ticket_number} to #{new_priority} " \
                        "(#{affected_user_count} users affected)"
    end
  end

  def self.generate_error_signature(error_class, error_message, stack_trace)
    # Create a signature from the first meaningful stack frame
    first_app_frame = stack_trace&.lines&.find { |l| l.include?('app/') || l.include?('lib/') }
    content = "#{error_class}|#{error_message&.gsub(/\d+/, 'N')}|#{first_app_frame}"
    Digest::SHA256.hexdigest(content)[0..16]
  end

  # Generate fingerprint from title+description for non-error tickets
  def self.generate_content_fingerprint(title, description = nil)
    normalized = normalize_for_comparison("#{title} #{description}")
    Digest::SHA256.hexdigest(normalized)[0..16]
  end

  # Normalize text for comparison (remove noise, lowercase, strip numbers)
  def self.normalize_for_comparison(text)
    return '' if text.blank?

    text.downcase
        .gsub(/[^a-z\s]/, '')  # Remove non-alpha
        .gsub(/\s+/, ' ')      # Collapse whitespace
        .strip
  end

  # Word-level similarity (Jaccard index)
  def self.word_similarity(a, b)
    return 0.0 if a.blank? || b.blank?

    words_a = a.split.reject { |w| w.length < 3 }.to_set
    words_b = b.split.reject { |w| w.length < 3 }.to_set

    return 0.0 if words_a.empty? || words_b.empty?

    intersection = words_a & words_b
    union = words_a | words_b

    intersection.size.to_f / union.size
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

  # ═══════════════════════════════════════════════════════════════════════════
  # AMOS SIGNAL EMISSION
  # ═══════════════════════════════════════════════════════════════════════════

  def emit_ticket_created_signal
    signal_type = is_critical? ? 'critical_ticket' : 'error_spike'
    strength = case priority
               when 'critical' then 0.95
               when 'high' then 0.7
               when 'medium' then 0.4
               else 0.3
               end

    emit_amos_signal!(
      signal_type: signal_type,
      source: 'support_ticket',
      strength: strength,
      summary: "[#{priority.upcase}] #{title}",
      data: {
        ticket_id: id,
        ticket_number: ticket_number,
        priority: priority,
        category: category,
        source: source,
        error_class: error_class
      }
    )
  end
end

