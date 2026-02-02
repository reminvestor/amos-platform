# frozen_string_literal: true

module Api
  module V1
    # UserSkillsController - Manage user skills for review eligibility
    #
    # Users can:
    # - View their skills and proficiency levels
    # - See review eligibility status
    # - Request skill verification
    # - View their review history and stats
    #
    class UserSkillsController < Api::V1::BaseController
      before_action :set_skill, only: [:show, :request_verification]

      # GET /api/v1/user_skills
      # List current user's skills
      def index
        skills = UserSkill.where(user: current_user).order(:skill_type)
        
        render json: {
          success: true,
          skills: skills.map { |s| skill_json(s) },
          review_stats: BountyReview.stats_for(current_user),
          eligible_to_review: UserSkill::SKILL_TYPES.select { |type|
            eligibility = ReviewerEligibility.find_by(user: current_user, entity: current_entity, bounty_type: type)
            eligibility&.is_eligible?
          }
        }
      end

      # GET /api/v1/user_skills/:skill_type
      # Get details for a specific skill
      def show
        render json: {
          success: true,
          skill: skill_json(@skill, detailed: true)
        }
      end

      # POST /api/v1/user_skills
      # Declare a new skill
      def create
        skill_type = params[:skill_type]
        
        unless UserSkill::SKILL_TYPES.include?(skill_type)
          return render json: { 
            success: false, 
            error: "Invalid skill type. Valid types: #{UserSkill::SKILL_TYPES.join(', ')}" 
          }, status: :unprocessable_entity
        end

        skill = UserSkill.for_user_and_type(current_user, skill_type)
        
        # Check existing contributions in this area to set initial proficiency
        contribution_count = Contribution.where(user: current_user, entity: current_entity)
                                         .where(contribution_type: skill_type)
                                         .approved.count
        
        if contribution_count >= UserSkill::EXPERT_THRESHOLD
          skill.update!(proficiency_level: 'expert', verified_contributions: contribution_count, verified: true)
        elsif contribution_count >= UserSkill::INTERMEDIATE_THRESHOLD
          skill.update!(proficiency_level: 'intermediate', verified_contributions: contribution_count, verified: true)
        end

        # Refresh eligibility
        ReviewerEligibility.refresh_single!(user: current_user, entity: current_entity, bounty_type: skill_type)

        render json: {
          success: true,
          skill: skill_json(skill),
          message: "Skill declared. #{contribution_count} past contributions detected."
        }, status: :created
      end

      # POST /api/v1/user_skills/:skill_type/request_verification
      # Request manual verification of a skill
      def request_verification
        if @skill.verified?
          return render json: { success: false, error: "Skill is already verified" }, status: :unprocessable_entity
        end

        # Add to verification queue (metadata)
        @skill.metadata['verification_requested_at'] = Time.current.iso8601
        @skill.metadata['verification_notes'] = params[:notes]
        @skill.save!

        # Notify admins
        notify_admins_of_verification_request(@skill)

        render json: {
          success: true,
          message: "Verification request submitted. An admin will review your skill claim."
        }
      end

      # GET /api/v1/user_skills/review_history
      # Get review history for current user
      def review_history
        reviews = BountyReview.where(reviewer: current_user)
                             .includes(:bounty)
                             .order(created_at: :desc)
                             .limit(50)

        render json: {
          success: true,
          reviews: reviews.map { |r| review_json(r) },
          stats: BountyReview.stats_for(current_user)
        }
      end

      # GET /api/v1/user_skills/eligible_bounties
      # Get bounty types user is eligible to review
      def eligible_bounties
        eligibilities = ReviewerEligibility.where(user: current_user, entity: current_entity, is_eligible: true)
        
        render json: {
          success: true,
          eligible_types: eligibilities.map { |e|
            {
              bounty_type: e.bounty_type,
              priority: e.priority,
              reason: e.eligibility_reason,
              active_reviews: e.active_reviews
            }
          },
          pending_reviews: Bounty.pending_human_review
                                 .where(entity: current_entity)
                                 .where(bounty_type: eligibilities.pluck(:bounty_type))
                                 .count
        }
      end

      private

      def set_skill
        @skill = UserSkill.find_by!(user: current_user, skill_type: params[:skill_type] || params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: "Skill not found" }, status: :not_found
      end

      def skill_json(skill, detailed: false)
        json = {
          skill_type: skill.skill_type,
          proficiency_level: skill.proficiency_level,
          verified: skill.verified?,
          can_review: skill.can_review?,
          verified_contributions: skill.verified_contributions,
          reviews_completed: skill.reviews_completed,
          review_accuracy: skill.review_accuracy.to_f
        }

        if detailed
          json.merge!(
            endorsements: skill.endorsements,
            metadata: skill.metadata,
            thresholds: {
              intermediate: UserSkill::INTERMEDIATE_THRESHOLD,
              expert: UserSkill::EXPERT_THRESHOLD
            }
          )
        end

        json
      end

      def review_json(review)
        {
          id: review.id,
          bounty_id: review.bounty_id,
          bounty_title: review.bounty.title,
          bounty_type: review.bounty.bounty_type,
          decision: review.decision,
          notes: review.notes&.truncate(200),
          quality_assessment: review.quality_assessment,
          review_points: review.review_points.to_f,
          tokens_earned: review.tokens_earned.to_f,
          was_overturned: review.was_overturned,
          created_at: review.created_at.iso8601
        }
      end

      def notify_admins_of_verification_request(skill)
        User.where(role: 'admin').find_each do |admin|
          UserNotification.create(
            user: admin,
            entity: current_entity,
            notification_type: 'skill_verification_request',
            title: "Skill Verification Request",
            message: "#{current_user.email} requests verification for #{skill.skill_type} skill.",
            metadata: {
              user_id: current_user.id,
              skill_type: skill.skill_type,
              notes: skill.metadata['verification_notes']
            }
          )
        end
      rescue => e
        Rails.logger.warn "[UserSkills] Failed to notify admins: #{e.message}"
      end
    end
  end
end
