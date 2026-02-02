# frozen_string_literal: true

# BountyReview - Record of human review and reward for reviewing AI work
#
# Reviewers earn AMOS tokens for quality reviews:
# - Default: 10% of bounty points as review reward
# - Quality multiplier based on review history
# - Track if review was overturned (affects future rewards)
#
# Review quality criteria:
# - Thoroughness: Did they check all aspects?
# - Accuracy: Was the decision correct?
# - Timeliness: Did they review promptly?
# - Feedback: Did they provide useful feedback?
#
class BountyReview < ApplicationRecord
  belongs_to :bounty
  belongs_to :reviewer, class_name: 'User'
  belongs_to :entity
  belongs_to :external_agent_execution, optional: true
  belongs_to :overturned_by, class_name: 'User', optional: true

  # Review decisions
  DECISIONS = %w[approved rejected].freeze

  # Default review reward percentage (of bounty points)
  DEFAULT_REWARD_PERCENTAGE = 10.0

  # Quality multipliers based on review history
  QUALITY_MULTIPLIERS = {
    excellent: 1.5,   # 95%+ accuracy, 50+ reviews
    good: 1.2,        # 90%+ accuracy, 20+ reviews  
    standard: 1.0,    # Base rate
    poor: 0.5         # < 80% accuracy
  }.freeze

  # Validations
  validates :decision, presence: true, inclusion: { in: DECISIONS }
  validates :bounty_id, uniqueness: { scope: :reviewer_id }
  validates :quality_assessment, numericality: { in: 1..5 }, allow_nil: true

  # Scopes
  scope :approved, -> { where(decision: 'approved') }
  scope :rejected, -> { where(decision: 'rejected') }
  scope :pending_reward, -> { where(reward_processed: false) }
  scope :overturned, -> { where(was_overturned: true) }
  scope :upheld, -> { where(was_overturned: false) }
  scope :by_reviewer, ->(user) { where(reviewer: user) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  after_create :calculate_review_points
  after_create :update_reviewer_skill

  # ═══════════════════════════════════════════════════════════════════════════
  # CLASS METHODS
  # ═══════════════════════════════════════════════════════════════════════════

  # Create a review record and reward
  def self.record_review!(bounty:, reviewer:, decision:, notes: nil, quality_assessment: nil, criteria_scores: {})
    execution = ExternalAgentExecution.find_by(bounty: bounty, awaiting_human_review: true)
    
    create!(
      bounty: bounty,
      reviewer: reviewer,
      entity: bounty.entity,
      decision: decision,
      notes: notes,
      quality_assessment: quality_assessment,
      criteria_scores: criteria_scores,
      external_agent_execution: execution
    )
  end

  # Get reviewer stats
  def self.stats_for(user)
    reviews = by_reviewer(user)
    
    {
      total_reviews: reviews.count,
      approved: reviews.approved.count,
      rejected: reviews.rejected.count,
      overturned: reviews.overturned.count,
      accuracy: reviews.any? ? ((1 - reviews.overturned.count.to_f / reviews.count) * 100).round(1) : 100.0,
      total_points_earned: reviews.sum(:review_points),
      total_tokens_earned: reviews.sum(:tokens_earned),
      pending_rewards: reviews.pending_reward.sum(:review_points)
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # INSTANCE METHODS
  # ═══════════════════════════════════════════════════════════════════════════

  # Calculate review reward points
  def calculate_review_points
    base_points = bounty.points * (bounty.review_reward_percentage || DEFAULT_REWARD_PERCENTAGE) / 100
    multiplier = quality_multiplier_for_reviewer
    
    update!(
      review_points: (base_points * multiplier).round(2),
      tokens_earned: 0  # Tokens calculated in daily pool distribution
    )
  end

  # Get quality multiplier based on reviewer's history
  def quality_multiplier_for_reviewer
    stats = BountyReview.stats_for(reviewer)
    
    if stats[:total_reviews] >= 50 && stats[:accuracy] >= 95
      QUALITY_MULTIPLIERS[:excellent]
    elsif stats[:total_reviews] >= 20 && stats[:accuracy] >= 90
      QUALITY_MULTIPLIERS[:good]
    elsif stats[:accuracy] < 80
      QUALITY_MULTIPLIERS[:poor]
    else
      QUALITY_MULTIPLIERS[:standard]
    end
  end

  # Overturn this review (admin action)
  def overturn!(by:, reason:)
    return false if was_overturned?
    
    update!(
      was_overturned: true,
      overturned_by: by,
      overturn_reason: reason
    )
    
    # Update reviewer's skill accuracy
    update_reviewer_skill_accuracy(upheld: false)
    
    # Reduce/remove reward
    update!(review_points: 0, tokens_earned: 0)
    
    true
  end

  # Mark reward as processed
  def mark_reward_processed!(tokens:)
    update!(
      reward_processed: true,
      tokens_earned: tokens
    )
  end

  # Was this a good review?
  def upheld?
    !was_overturned?
  end

  def approved?
    decision == 'approved'
  end

  def rejected?
    decision == 'rejected'
  end

  def to_api_response
    {
      id: id,
      bounty_id: bounty_id,
      reviewer_id: reviewer_id,
      reviewer_email: reviewer.email,
      decision: decision,
      notes: notes,
      quality_assessment: quality_assessment,
      criteria_scores: criteria_scores,
      review_points: review_points.to_f,
      tokens_earned: tokens_earned.to_f,
      was_overturned: was_overturned,
      created_at: created_at.iso8601
    }
  end

  private

  def update_reviewer_skill
    skill = UserSkill.for_user_and_type(reviewer, bounty.bounty_type)
    skill.record_review!(upheld: true)
  end

  def update_reviewer_skill_accuracy(upheld:)
    skill = UserSkill.find_by(user: reviewer, skill_type: bounty.bounty_type)
    skill&.record_review!(upheld: upheld)
  end
end
