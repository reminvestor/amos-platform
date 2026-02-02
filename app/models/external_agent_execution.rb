# frozen_string_literal: true

# ExternalAgentExecution - Tracks a bounty execution by an external agent
#
# Created when an external agent claims a bounty, tracks the entire
# lifecycle from claim → work → submission → review → completion.
#
class ExternalAgentExecution < ApplicationRecord
  # Associations
  belongs_to :external_agent_registration
  belongs_to :bounty
  belongs_to :entity
  belongs_to :reviewed_by, class_name: 'User', optional: true
  
  has_many :external_agent_tool_calls, dependent: :destroy
  has_one :contribution, dependent: :nullify

  # Delegate to registration
  delegate :operator, :agent_name, :agent_platform, to: :external_agent_registration

  # Status progression
  STATUSES = %w[in_progress submitted approved rejected expired cancelled].freeze

  # Validations
  validates :status, inclusion: { in: STATUSES }
  validates :bounty_id, uniqueness: { scope: :external_agent_registration_id, message: 'already claimed by this agent' }

  # Scopes
  scope :in_progress, -> { where(status: 'in_progress') }
  scope :submitted, -> { where(status: 'submitted') }
  scope :pending_review, -> { where(status: 'submitted') }
  scope :approved, -> { where(status: 'approved') }
  scope :rejected, -> { where(status: 'rejected') }
  scope :completed, -> { where(status: %w[approved rejected]) }
  scope :completed_recently, -> { approved.where('reviewed_at > ?', 7.days.ago).order(reviewed_at: :desc) }
  scope :expired, -> { where(status: 'expired') }
  scope :active, -> { where(status: %w[in_progress submitted]) }
  scope :for_agent, ->(agent) { where(external_agent_registration: agent) }
  scope :for_bounty, ->(bounty) { where(bounty: bounty) }

  # Callbacks
  before_create :set_defaults
  after_create :update_bounty_status
  after_update :handle_status_change, if: :saved_change_to_status?

  # ═══════════════════════════════════════════════════════════════════════════
  # LIFECYCLE
  # ═══════════════════════════════════════════════════════════════════════════

  def self.create_for_bounty!(agent:, bounty:, approach: nil)
    raise ArgumentError, "Agent cannot claim this bounty" unless agent.can_claim_bounty?(bounty)
    raise ArgumentError, "Bounty is not available" unless bounty.can_claim?
    
    transaction do
      execution = create!(
        external_agent_registration: agent,
        bounty: bounty,
        entity: bounty.entity,
        status: 'in_progress',
        started_at: Time.current,
        expires_at: 24.hours.from_now,
        submission_data: { approach: approach }
      )
      
      # Update bounty and agent stats
      bounty.claim!(agent.operator)
      agent.record_bounty_claimed!
      
      execution
    end
  end

  def submit!(work_summary:, deliverables:, work_log: nil)
    return false unless status == 'in_progress'
    return false if expired?
    
    update!(
      status: 'submitted',
      submitted_at: Time.current,
      work_log: work_log,
      submission_data: submission_data.merge(
        work_summary: work_summary,
        deliverables: deliverables,
        tools_used_summary: tools_used.map { |t| t['tool_name'] }.uniq
      )
    )
    
    # Update bounty
    bounty.submit!(notes: work_summary)
    
    # Schedule AI review
    schedule_ai_review!
    
    true
  end

  def approve!(reviewer: nil, quality_score: nil, tokens_awarded: nil, notes: nil)
    return false unless status == 'submitted'
    
    tokens = tokens_awarded || bounty.effective_points
    
    transaction do
      update!(
        status: 'approved',
        reviewed_at: Time.current,
        reviewed_by: reviewer,
        quality_score: quality_score || 75.0,
        review_notes: notes,
        tokens_awarded: tokens
      )
      
      # Update bounty
      bounty.approve!(reviewer: reviewer || external_agent_registration.operator, final_points: tokens)
      
      # Update agent stats
      external_agent_registration.record_bounty_completed!(tokens)
      
      # Create contribution for token economy
      create_contribution!
    end
    
    true
  end

  def reject!(reviewer: nil, notes: nil)
    return false unless status == 'submitted'
    
    transaction do
      update!(
        status: 'rejected',
        reviewed_at: Time.current,
        reviewed_by: reviewer,
        quality_score: review_result['quality_score'] || 0,
        review_notes: notes
      )
      
      # Release bounty for others
      bounty.reject!(reviewer: reviewer, notes: "External agent submission rejected: #{notes}")
      
      # Update agent stats
      external_agent_registration.record_bounty_rejected!
    end
    
    true
  end

  def cancel!
    return false unless status == 'in_progress'
    
    update!(status: 'cancelled')
    bounty.release_claim!
    
    true
  end

  def expire!
    return false unless status == 'in_progress'
    return false unless expired?
    
    update!(status: 'expired')
    bounty.release_claim!
    
    true
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TOOL EXECUTION
  # ═══════════════════════════════════════════════════════════════════════════

  def can_execute_tool?(tool_name)
    return false unless status == 'in_progress'
    return false if expired?
    return false unless external_agent_registration.can_use_tool?(tool_name)
    return false if tool_calls_count >= external_agent_registration.tool_calls_per_bounty
    
    true
  end

  def record_tool_call!(tool_name:, arguments:, result:, success:, latency_ms:, policy_allowed: true, policy_rule: nil, error: nil)
    tool_call = external_agent_tool_calls.create!(
      external_agent_registration: external_agent_registration,
      tool_name: tool_name,
      arguments: arguments,
      result: result,
      success: success,
      latency_ms: latency_ms,
      error_message: error,
      policy_allowed: policy_allowed,
      policy_rule_applied: policy_rule,
      executed_at: Time.current
    )
    
    # Update tools_used array
    self.tools_used = tools_used + [{
      tool_name: tool_name,
      success: success,
      timestamp: Time.current.iso8601
    }]
    
    increment!(:tool_calls_count)
    external_agent_registration.record_tool_call!
    
    tool_call
  end

  def tool_calls_remaining
    [external_agent_registration.tool_calls_per_bounty - tool_calls_count, 0].max
  end

  def time_remaining
    return nil unless expires_at.present?
    return 0 if expired?
    
    (expires_at - Time.current).to_i
  end

  def time_remaining_formatted
    seconds = time_remaining
    return 'Expired' if seconds.nil? || seconds <= 0
    
    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    "#{hours}h #{minutes}m"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # AI REVIEW
  # ═══════════════════════════════════════════════════════════════════════════

  def schedule_ai_review!
    # Queue background job for AI review
    ExternalAgentReviewJob.perform_later(id)
  end

  def perform_ai_review!
    return unless status == 'submitted'
    
    reviewer = AmosWorkReviewer.new(entity: entity)
    result = reviewer.review_external_agent_work(
      bounty: bounty,
      submission: submission_data,
      work_log: work_log,
      tools_used: tools_used
    )
    
    update!(
      review_result: result,
      ai_pre_review_passed: result['approved'],
      quality_score: result['quality_score']
    )
    
    # Record AI review on bounty
    bounty.record_ai_review!(result)
    
    if result['approved']
      # AI passed - now queue for human review (ALWAYS required)
      queue_for_human_review!
    else
      # AI rejected - still needs human confirmation for external agents
      # This prevents gaming by resubmitting until AI passes
      queue_for_human_review!(ai_rejected: true)
    end
  end

  # Queue for human review instead of auto-approving
  def queue_for_human_review!(ai_rejected: false)
    update!(
      awaiting_human_review: true,
      review_notes: ai_rejected ? "AI pre-review: REJECTED - Requires human confirmation" : "AI pre-review: PASSED - Awaiting human approval"
    )
    
    bounty.update!(status: 'reviewing')
    
    # Notify appropriate reviewer
    notify_reviewer_needed!
    
    Rails.logger.info "[ExternalAgent] Execution #{id} queued for human review (AI passed: #{!ai_rejected})"
  end

  # Human approves the work
  def human_approve!(reviewer:, notes: nil, final_points: nil)
    return { success: false, error: "Not awaiting human review" } unless awaiting_human_review?
    return { success: false, error: "You cannot review this bounty" } unless bounty.can_be_reviewed_by?(reviewer)

    tokens = final_points || review_result['recommended_tokens'] || bounty.effective_points

    transaction do
      update!(
        status: 'approved',
        reviewed_at: Time.current,
        reviewed_by: reviewer,
        human_reviewer_id: reviewer.id,
        human_review_at: Time.current,
        human_review_notes: notes,
        tokens_awarded: tokens,
        awaiting_human_review: false
      )

      # Approve the bounty with human review
      bounty.human_approve!(reviewer: reviewer, notes: notes, final_points: tokens)

      # Update agent stats
      external_agent_registration.record_bounty_completed!(tokens)
    end

    { success: true, tokens_awarded: tokens }
  end

  # Human rejects the work
  def human_reject!(reviewer:, notes:)
    return { success: false, error: "Not awaiting human review" } unless awaiting_human_review?
    return { success: false, error: "You cannot review this bounty" } unless bounty.can_be_reviewed_by?(reviewer)

    transaction do
      update!(
        status: 'rejected',
        reviewed_at: Time.current,
        reviewed_by: reviewer,
        human_reviewer_id: reviewer.id,
        human_review_at: Time.current,
        human_review_notes: notes,
        awaiting_human_review: false
      )

      # Reject the bounty with human review
      bounty.human_reject!(reviewer: reviewer, notes: notes)

      # Update agent stats
      external_agent_registration.record_bounty_rejected!
    end

    { success: true }
  end

  def awaiting_human_review?
    awaiting_human_review == true
  end

  def notify_reviewer_needed!
    # Determine who should review
    reviewer = bounty.required_reviewer
    
    if reviewer.present?
      # Notify specific user
      UserNotification.create(
        user: reviewer,
        entity: entity,
        notification_type: 'bounty_review_needed',
        title: "Bounty Review Needed: #{bounty.title}",
        message: "An external agent has submitted work for your bounty. Please review.",
        metadata: {
          bounty_id: bounty.id,
          execution_id: id,
          agent_name: external_agent_registration.agent_name,
          ai_passed: ai_pre_review_passed
        }
      )
    else
      # System bounty - notify admins
      User.where(role: 'admin').find_each do |admin|
        UserNotification.create(
          user: admin,
          entity: entity,
          notification_type: 'system_bounty_review_needed',
          title: "System Bounty Review: #{bounty.title}",
          message: "A system bounty completed by external agent requires admin review.",
          metadata: {
            bounty_id: bounty.id,
            execution_id: id,
            agent_name: external_agent_registration.agent_name,
            ai_passed: ai_pre_review_passed
          }
        )
      end
    end
  rescue => e
    Rails.logger.warn "[ExternalAgent] Failed to send review notification: #{e.message}"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # API RESPONSES
  # ═══════════════════════════════════════════════════════════════════════════

  def to_summary
    {
      id: id,
      bounty_id: bounty_id,
      bounty_title: bounty.title,
      bounty_type: bounty.bounty_type,
      points: bounty.points,
      status: status,
      started_at: started_at&.iso8601,
      submitted_at: submitted_at&.iso8601,
      reviewed_at: reviewed_at&.iso8601,
      tokens_awarded: tokens_awarded&.to_f,
      quality_score: quality_score&.to_f
    }
  end

  def to_api_response
    {
      id: id,
      bounty: {
        id: bounty.id,
        title: bounty.title,
        description: bounty.description,
        bounty_type: bounty.bounty_type,
        points: bounty.points
      },
      status: status,
      tool_calls_count: tool_calls_count,
      tool_calls_remaining: tool_calls_remaining,
      time_remaining: time_remaining_formatted,
      expires_at: expires_at&.iso8601,
      started_at: started_at&.iso8601,
      submitted_at: submitted_at&.iso8601,
      reviewed_at: reviewed_at&.iso8601,
      quality_score: quality_score&.to_f,
      tokens_awarded: tokens_awarded&.to_f,
      review_notes: review_notes
    }
  end

  private

  def set_defaults
    self.tools_used ||= []
    self.tool_calls_count ||= 0
    self.submission_data ||= {}
    self.review_result ||= {}
  end

  def update_bounty_status
    bounty.start_work! if bounty.claimed?
  end

  def handle_status_change
    case status
    when 'approved'
      Rails.logger.info "[ExternalAgent] Execution #{id} approved, #{tokens_awarded} tokens awarded"
    when 'rejected'
      Rails.logger.info "[ExternalAgent] Execution #{id} rejected: #{review_notes}"
    when 'expired'
      Rails.logger.info "[ExternalAgent] Execution #{id} expired"
    end
  end

  def create_contribution!
    Contribution.create!(
      user: operator,
      entity: entity,
      title: "External Agent: #{bounty.title}",
      description: "Completed via external agent (#{agent_name}) on #{agent_platform} platform",
      contribution_type: bounty_contribution_type,
      status: :approved,
      reviewed_by: reviewed_by,
      reviewed_at: reviewed_at,
      stake_value: tokens_awarded,
      external_reference: "bounty:#{bounty.id}|external_agent:#{external_agent_registration.id}|execution:#{id}"
    )
  end

  def bounty_contribution_type
    case bounty.bounty_type
    when 'bug' then 'bug_fix'
    when 'feature' then 'feature'
    when 'documentation' then 'documentation'
    when 'content', 'marketing' then 'content'
    when 'support' then 'support'
    when 'translation' then 'translation'
    when 'design' then 'design'
    when 'testing' then 'testing'
    else 'code'
    end
  end
end
