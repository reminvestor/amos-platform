# frozen_string_literal: true

# UserSkill - Tracks user expertise areas for reviewing AI-generated work
#
# Users need appropriate skills to review bounties:
# - Skills map to bounty types (bug, documentation, design, etc.)
# - Skills are verified through contribution history
# - Verified skills unlock reviewer eligibility
#
# Proficiency levels:
# - beginner: < 5 approved contributions, can't review
# - intermediate: 5-20 contributions, can review with oversight
# - expert: 20+ contributions, trusted reviewer
#
class UserSkill < ApplicationRecord
  belongs_to :user

  # Skill types map directly to bounty types
  SKILL_TYPES = %w[
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
    code_review
  ].freeze

  PROFICIENCY_LEVELS = %w[beginner intermediate expert].freeze

  # Thresholds for proficiency
  INTERMEDIATE_THRESHOLD = 5
  EXPERT_THRESHOLD = 20

  # Validations
  validates :skill_type, presence: true, inclusion: { in: SKILL_TYPES }
  validates :proficiency_level, inclusion: { in: PROFICIENCY_LEVELS }
  validates :user_id, uniqueness: { scope: :skill_type }
  validates :review_accuracy, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  # Scopes
  scope :verified, -> { where(verified: true) }
  scope :for_type, ->(type) { where(skill_type: type) }
  scope :reviewable, -> { where(proficiency_level: %w[intermediate expert]) }
  scope :expert, -> { where(proficiency_level: 'expert') }

  # ═══════════════════════════════════════════════════════════════════════════
  # CLASS METHODS
  # ═══════════════════════════════════════════════════════════════════════════

  # Find or create skill for a user
  def self.for_user_and_type(user, skill_type)
    find_or_create_by(user: user, skill_type: skill_type) do |skill|
      skill.proficiency_level = 'beginner'
    end
  end

  # Get users eligible to review a bounty type
  def self.eligible_reviewers_for(bounty_type, entity: nil, limit: 10)
    query = verified
              .for_type(bounty_type)
              .reviewable
              .joins(:user)
              .where(users: { active: true })
              .order(proficiency_level: :desc, review_accuracy: :desc)

    query = query.where(users: { entity_id: entity.id }) if entity.present?
    query.limit(limit).map(&:user)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # INSTANCE METHODS
  # ═══════════════════════════════════════════════════════════════════════════

  # Can this skill holder review?
  def can_review?
    verified? && proficiency_level.in?(%w[intermediate expert])
  end

  # Is this an expert-level skill?
  def expert?
    proficiency_level == 'expert'
  end

  # Record a successful contribution in this skill area
  def record_contribution!
    increment!(:verified_contributions)
    update_proficiency!
    verify! if should_auto_verify?
  end

  # Record a completed review
  def record_review!(upheld: true)
    increment!(:reviews_completed)
    
    # Update accuracy (weighted average)
    total = reviews_completed
    current_accuracy = review_accuracy || 100.0
    new_accuracy = if upheld
      ((current_accuracy * (total - 1)) + 100) / total
    else
      ((current_accuracy * (total - 1)) + 0) / total
    end
    
    update!(review_accuracy: new_accuracy.round(2))
  end

  # Add an endorsement from another user
  def add_endorsement!(endorser:, notes: nil)
    return false if endorser == user
    return false if endorsements.any? { |e| e['user_id'] == endorser.id }
    
    endorsements << {
      user_id: endorser.id,
      user_email: endorser.email,
      notes: notes,
      endorsed_at: Time.current.iso8601
    }
    save!
    
    # Auto-verify if enough endorsements from experts
    verify! if should_auto_verify?
    true
  end

  # Manually verify this skill (admin action)
  def verify!(reason: 'manual')
    update!(
      verified: true,
      metadata: metadata.merge(
        verified_at: Time.current.iso8601,
        verified_reason: reason
      )
    )
  end

  # Revoke verification
  def unverify!(reason:)
    update!(
      verified: false,
      metadata: metadata.merge(
        unverified_at: Time.current.iso8601,
        unverified_reason: reason
      )
    )
  end

  # Display label
  def display_name
    "#{skill_type.titleize} (#{proficiency_level})"
  end

  private

  def update_proficiency!
    new_level = case verified_contributions
    when 0...INTERMEDIATE_THRESHOLD then 'beginner'
    when INTERMEDIATE_THRESHOLD...EXPERT_THRESHOLD then 'intermediate'
    else 'expert'
    end
    
    update!(proficiency_level: new_level) if proficiency_level != new_level
  end

  def should_auto_verify?
    return true if verified_contributions >= INTERMEDIATE_THRESHOLD
    return true if endorsements.count >= 3
    false
  end
end
