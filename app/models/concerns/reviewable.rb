# frozen_string_literal: true

# Reviewable Concern
#
# Provides shared publication workflow functionality for user-created resources
# that can be made public (agents, tools, integrations).
#
# Includes:
# - Publication status management (private, pending_review, approved, rejected)
# - Security rating tracking (pass, review, fail)
# - Admin review workflow
# - Reputation scoring based on usage and feedback
#
# Usage:
#   class AgentPlugin < ApplicationRecord
#     include Reviewable
#   end
#
module Reviewable
  extend ActiveSupport::Concern

  PUBLISH_STATUSES = %w[private pending_review approved rejected].freeze
  SECURITY_RATINGS = %w[pass review fail].freeze

  included do
    # Associations
    belongs_to :reviewed_by, class_name: 'User', optional: true

    # Validations
    validates :publish_status, inclusion: { in: PUBLISH_STATUSES }, allow_nil: true
    validates :security_rating, inclusion: { in: SECURITY_RATINGS }, allow_nil: true

    # Scopes
    scope :public_approved, -> { where(is_public: true, publish_status: 'approved') }
    scope :public_pending, -> { where(is_public: true, publish_status: 'pending_review') }
    scope :pending_review, -> { where(publish_status: 'pending_review') }
    scope :private_only, -> { where(is_public: false) }
    scope :with_security_rating, ->(rating) { where(security_rating: rating) }
    scope :safe_to_use, -> { where.not(security_rating: 'fail') }
    scope :needs_security_review, -> { where(security_rating: 'review') }

    # Callbacks
    before_save :set_published_at, if: :becoming_public?
  end

  # ============================================
  # PUBLICATION WORKFLOW
  # ============================================

  # Request publication - triggers security review
  def request_publication!
    return false unless can_request_publication?

    # Run security check first
    run_security_check!

    if security_rating == 'fail'
      update!(
        is_public: false,
        publish_status: 'rejected',
        review_notes: "Automatically rejected due to security concerns: #{security_reason}"
      )
      return false
    end

    update!(
      is_public: true,
      publish_status: security_rating == 'pass' ? 'approved' : 'pending_review'
    )

    # If auto-approved (security pass), set published_at
    if publish_status == 'approved'
      update!(published_at: Time.current)
    end

    true
  end

  # Admin approves publication
  def approve_publication!(reviewer, notes: nil)
    update!(
      publish_status: 'approved',
      reviewed_by: reviewer,
      reviewed_at: Time.current,
      review_notes: notes,
      published_at: Time.current
    )
  end

  # Admin rejects publication
  def reject_publication!(reviewer, reason)
    update!(
      publish_status: 'rejected',
      is_public: false,
      reviewed_by: reviewer,
      reviewed_at: Time.current,
      review_notes: reason
    )
  end

  # Unpublish (make private again)
  def unpublish!
    update!(
      is_public: false,
      publish_status: 'private',
      published_at: nil
    )
  end

  # ============================================
  # STATUS CHECKS
  # ============================================

  def public?
    is_public && publish_status == 'approved'
  end

  def pending_review?
    publish_status == 'pending_review'
  end

  def rejected?
    publish_status == 'rejected'
  end

  def can_request_publication?
    # Must be owned by a user (not system) and currently private
    respond_to?(:user_id) && user_id.present? && !is_public
  end

  def safe_to_execute?
    security_rating != 'fail'
  end

  def needs_manual_review?
    security_rating == 'review' || publish_status == 'pending_review'
  end

  # ============================================
  # SECURITY
  # ============================================

  def run_security_check!
    result = security_check_service.evaluate(self)
    
    update!(
      security_rating: result['rating'],
      security_reason: result['reason']
    )
    
    result
  rescue => e
    Rails.logger.error "Security check failed for #{self.class.name} #{id}: #{e.message}"
    update!(
      security_rating: 'review',
      security_reason: "Security check failed: #{e.message}. Manual review required."
    )
  end

  # ============================================
  # REPUTATION
  # ============================================

  def increment_usage!
    increment!(:usage_count)
  end

  # Calculate reputation score (0.0 to 1.0)
  # Override in including class for custom logic
  def reputation_score
    base_score = 0.5

    # Factor 1: Usage popularity (up to 0.2 bonus)
    usage_bonus = [usage_count.to_f / 1000, 0.2].min
    base_score += usage_bonus

    # Factor 2: Security rating
    case security_rating
    when 'pass'
      base_score += 0.1
    when 'review'
      base_score -= 0.1
    when 'fail'
      base_score -= 0.5
    end

    # Factor 3: User feedback (if feedbacks association exists)
    if respond_to?(:user_satisfaction_score)
      feedback_score = user_satisfaction_score
      base_score += (feedback_score - 0.5) * 0.4  # -0.2 to +0.2
    end

    base_score.clamp(0.0, 1.0)
  end

  # ============================================
  # DISCOVERY PRIORITY
  # ============================================

  # Returns a tier for discovery ordering
  # Lower tier = higher priority
  def discovery_tier
    return 1 if system_resource?          # System resources (tier 1)
    return 2 if entity_specific?          # Entity-owned (tier 2)
    return 3 if public? && approved?      # Public approved (tier 3)
    return 4 if public? && pending_review? # Public pending (tier 4)
    5 # Private or rejected (tier 5)
  end

  def system_resource?
    # System resources have no user_id
    respond_to?(:user_id) && user_id.nil?
  end

  def entity_specific?
    respond_to?(:entity_id) && entity_id.present? && !public?
  end

  private

  def becoming_public?
    is_public_changed? && is_public && publish_status == 'approved'
  end

  def set_published_at
    self.published_at ||= Time.current if publish_status == 'approved'
  end

  def security_check_service
    # Use AgentSecurityCheckService for agents, SecurityCheckService for tools
    if is_a?(AgentPlugin)
      AgentSecurityCheckService.new
    elsif is_a?(ToolDefinition)
      SecurityCheckService.new
    else
      # Generic security check
      AgentSecurityCheckService.new
    end
  end
end

