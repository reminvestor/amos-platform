# frozen_string_literal: true

# Bounty - Work items with point values for the token economy
#
# Bounties can be created by:
# 1. AMOS during nightly thinking time (autonomous)
# 2. Users/admins manually
# 3. Automatically from support tickets
# 4. From voted feature requests
#
# The point value is scored by AI based on:
# - Estimated effort (hours)
# - User impact (how many people affected)
# - Urgency (how soon is this needed)
# - Complexity (technical difficulty)
#
class Bounty < ApplicationRecord
  belongs_to :entity
  belongs_to :created_by, class_name: 'User', optional: true  # nil = AMOS created
  belongs_to :claimed_by, class_name: 'User', optional: true
  belongs_to :reviewed_by, class_name: 'User', optional: true
  belongs_to :support_ticket, optional: true

  has_one :contribution, dependent: :nullify

  # Bounty types
  BOUNTY_TYPES = %w[
    bug
    feature
    documentation
    content
    marketing
    support
    translation
    design
    testing
    infrastructure
  ].freeze

  # Status flow
  STATUSES = %w[
    open
    claimed
    in_progress
    submitted
    reviewing
    approved
    rejected
    expired
    cancelled
  ].freeze

  # Sources
  SOURCES = %w[
    amos_thinking
    user_submitted
    admin_created
    log_monitor
    feature_vote
    support_ticket
  ].freeze

  # Validations
  validates :title, presence: true
  validates :bounty_type, inclusion: { in: BOUNTY_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :points, numericality: { greater_than: 0 }
  validates :source, inclusion: { in: SOURCES }, allow_nil: true

  # Scopes
  scope :open_bounties, -> { where(status: 'open') }
  scope :available, -> { where(status: 'open').where('expires_at IS NULL OR expires_at > ?', Time.current) }
  scope :claimed, -> { where(status: %w[claimed in_progress]) }
  scope :pending_review, -> { where(status: %w[submitted reviewing]) }
  scope :completed, -> { where(status: 'approved') }
  scope :by_type, ->(type) { where(bounty_type: type) }
  scope :by_points, -> { order(points: :desc) }
  scope :by_urgency, -> { order(urgency_score: :desc) }
  scope :created_by_amos, -> { where(created_by: nil) }
  scope :created_by_users, -> { where.not(created_by: nil) }
  scope :recent, -> { order(created_at: :desc) }
  scope :high_value, -> { where('points >= ?', 200) }
  scope :quick_wins, -> { where('points <= ?', 50) }

  # Callbacks
  before_validation :set_defaults, on: :create
  after_update :sync_completion_to_source, if: :just_approved?

  # ═══════════════════════════════════════════════════════════════════════════
  # CREATION HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  # Create a bounty from AMOS thinking
  def self.create_from_amos!(entity:, title:, description:, bounty_type:, points:, scoring_rationale:, metadata: {})
    create!(
      entity: entity,
      title: title,
      description: description,
      bounty_type: bounty_type,
      points: points,
      ai_scoring_rationale: scoring_rationale,
      source: 'amos_thinking',
      metadata: metadata
    )
  end

  # Create a bounty from a support ticket
  def self.create_from_ticket!(ticket, points:, scoring_rationale:)
    bounty_type = case ticket.category
    when 'bug', 'performance', 'security' then 'bug'
    when 'feature_request' then 'feature'
    when 'documentation' then 'documentation'
    when 'ui_issue' then 'design'
    else 'bug'
    end

    create!(
      entity: ticket.entity,
      support_ticket: ticket,
      title: ticket.title,
      description: ticket.description,
      bounty_type: bounty_type,
      points: points,
      ai_scoring_rationale: scoring_rationale,
      source: 'support_ticket',
      urgency_score: ticket.is_critical? ? 10 : (ticket.priority == 'high' ? 7 : 5),
      metadata: { ticket_number: ticket.ticket_number }
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # STATUS TRANSITIONS
  # ═══════════════════════════════════════════════════════════════════════════

  def claim!(user)
    return false unless can_claim?

    update!(
      status: 'claimed',
      claimed_by: user,
      claimed_at: Time.current
    )
  end

  def start_work!
    return false unless claimed?

    update!(status: 'in_progress')
  end

  def submit!(notes: nil)
    return false unless status.in?(%w[claimed in_progress])

    update!(
      status: 'submitted',
      submitted_at: Time.current,
      submission_notes: notes
    )
  end

  def start_review!(reviewer)
    return false unless status == 'submitted'

    update!(
      status: 'reviewing',
      reviewed_by: reviewer
    )
  end

  def approve!(reviewer: nil, final_points: nil, notes: nil)
    return false unless status.in?(%w[submitted reviewing])

    update!(
      status: 'approved',
      reviewed_by: reviewer || reviewed_by,
      approved_at: Time.current,
      final_points: final_points || points,
      review_notes: notes
    )

    # Create contribution record
    create_contribution_for_claimer!
  end

  def reject!(reviewer: nil, notes: nil)
    return false unless status.in?(%w[submitted reviewing])

    update!(
      status: 'rejected',
      reviewed_by: reviewer || reviewed_by,
      rejected_at: Time.current,
      review_notes: notes
    )

    # Release for others to claim
    release_claim!
  end

  def cancel!(reason: nil)
    update!(
      status: 'cancelled',
      review_notes: reason
    )
  end

  def expire!
    update!(status: 'expired') if can_expire?
  end

  def release_claim!
    update!(
      claimed_by: nil,
      claimed_at: nil,
      status: 'open'
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # QUERIES
  # ═══════════════════════════════════════════════════════════════════════════

  def can_claim?
    status == 'open' && !expired?
  end

  def claimed?
    claimed_by.present? && status.in?(%w[claimed in_progress submitted reviewing])
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def can_expire?
    status == 'open' && expires_at.present? && expires_at < Time.current
  end

  def created_by_amos?
    created_by.nil?
  end

  def effective_points
    final_points || points
  end

  def to_board_display
    {
      id: id,
      title: title,
      description: description&.truncate(200),
      bounty_type: bounty_type,
      points: points,
      status: status,
      created_by: created_by_amos? ? 'AMOS' : created_by&.display_name,
      claimed_by: claimed_by&.display_name,
      urgency: urgency_score,
      created_at: created_at,
      upvotes: upvotes
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # VOTING
  # ═══════════════════════════════════════════════════════════════════════════

  def upvote!
    increment!(:upvotes)
  end

  def downvote!
    increment!(:downvotes)
  end

  def vote_score
    upvotes - downvotes
  end

  private

  def set_defaults
    self.status ||= 'open'
    self.source ||= created_by.present? ? 'user_submitted' : 'amos_thinking'
  end

  def just_approved?
    saved_change_to_status? && status == 'approved'
  end

  def sync_completion_to_source
    BountyIntegrationService.new(entity).sync_bounty_completion!(self)
  rescue => e
    Rails.logger.error "[BOUNTY] Failed to sync completion: #{e.message}"
  end

  def create_contribution_for_claimer!
    return unless claimed_by.present?

    Contribution.create!(
      user: claimed_by,
      entity: entity,
      title: "Completed bounty: #{title}",
      description: "Bounty ##{id} - #{description&.truncate(500)}",
      contribution_type: contribution_type_from_bounty,
      status: :approved,
      reviewed_by: reviewed_by,
      reviewed_at: Time.current,
      stake_value: effective_points,
      external_reference: "bounty:#{id}"
    )
  end

  def contribution_type_from_bounty
    case bounty_type
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
