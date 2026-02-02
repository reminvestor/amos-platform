# frozen_string_literal: true

# ReviewerEligibility - Tracks who can review which bounty types
#
# Eligibility is determined by:
# 1. Verified skills in the bounty type area
# 2. Admin status (admins can review anything)
# 3. Being the bounty creator/funder (can review their own)
# 4. Contribution history in the area
#
# Priority determines who gets offered reviews first:
# - Experts > Intermediate
# - High accuracy > Low accuracy
# - Lower active review count > Higher
#
class ReviewerEligibility < ApplicationRecord
  # The migration created this table with singular name
  self.table_name = 'reviewer_eligibility'
  
  belongs_to :user
  belongs_to :entity

  ELIGIBILITY_REASONS = %w[
    verified_skill
    admin
    creator
    contribution_history
    manual_grant
  ].freeze

  # Validations
  validates :bounty_type, presence: true
  validates :user_id, uniqueness: { scope: [:entity_id, :bounty_type] }
  validates :eligibility_reason, inclusion: { in: ELIGIBILITY_REASONS }, allow_nil: true

  # Scopes
  scope :eligible, -> { where(is_eligible: true) }
  scope :for_type, ->(type) { where(bounty_type: type) }
  scope :available, -> { eligible.where('active_reviews < 5') }
  scope :by_priority, -> { order(priority: :desc, last_review_at: :asc) }

  # ═══════════════════════════════════════════════════════════════════════════
  # CLASS METHODS
  # ═══════════════════════════════════════════════════════════════════════════

  # Find eligible reviewers for a bounty
  def self.find_reviewers_for(bounty, limit: 5)
    available
      .for_type(bounty.bounty_type)
      .where(entity: bounty.entity)
      .by_priority
      .limit(limit)
      .includes(:user)
      .map(&:user)
  end

  # Refresh eligibility for a user across all bounty types
  def self.refresh_for_user!(user, entity:)
    UserSkill::SKILL_TYPES.each do |skill_type|
      refresh_single!(user: user, entity: entity, bounty_type: skill_type)
    end
  end

  # Refresh eligibility for a single skill/bounty type
  def self.refresh_single!(user:, entity:, bounty_type:)
    eligibility = find_or_initialize_by(user: user, entity: entity, bounty_type: bounty_type)
    
    # Check various eligibility sources
    skill = UserSkill.find_by(user: user, skill_type: bounty_type)
    
    if user.admin?
      eligibility.assign_attributes(
        is_eligible: true,
        eligibility_reason: 'admin',
        priority: 100
      )
    elsif skill&.can_review?
      priority = skill.expert? ? 80 : 50
      priority += (skill.review_accuracy.to_f / 10).to_i  # Add up to 10 points for accuracy
      
      eligibility.assign_attributes(
        is_eligible: true,
        eligibility_reason: 'verified_skill',
        priority: priority
      )
    else
      # Check contribution history
      contribution_count = Contribution.where(user: user, entity: entity)
                                       .where(contribution_type: bounty_type)
                                       .approved.count
      
      if contribution_count >= 3
        eligibility.assign_attributes(
          is_eligible: true,
          eligibility_reason: 'contribution_history',
          priority: 30
        )
      else
        eligibility.assign_attributes(
          is_eligible: false,
          eligibility_reason: nil,
          priority: 0
        )
      end
    end
    
    eligibility.save!
    eligibility
  end

  # Grant manual eligibility
  def self.grant!(user:, entity:, bounty_type:, priority: 50)
    eligibility = find_or_initialize_by(user: user, entity: entity, bounty_type: bounty_type)
    eligibility.update!(
      is_eligible: true,
      eligibility_reason: 'manual_grant',
      priority: priority
    )
    eligibility
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # INSTANCE METHODS
  # ═══════════════════════════════════════════════════════════════════════════

  # Assign a review to this reviewer
  def assign_review!
    increment!(:active_reviews)
    update!(last_review_at: Time.current)
  end

  # Complete a review
  def complete_review!
    decrement!(:active_reviews)
    self.active_reviews = [active_reviews, 0].max
    save!
  end

  # Is this reviewer available?
  def available?
    is_eligible? && active_reviews < 5
  end
end
