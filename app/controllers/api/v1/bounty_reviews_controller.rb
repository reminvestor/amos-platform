# frozen_string_literal: true

module Api
  module V1
    # BountyReviewsController - Human review of bounty submissions
    #
    # All bounty completions (especially from external agents) require human review:
    # - System bounties (created by AMOS) → Platform admin must review
    # - User-funded bounties → Creator/funder reviews
    # - User-created bounties → Creator reviews
    #
    class BountyReviewsController < Api::V1::BaseController
      before_action :set_bounty, only: [:show, :approve, :reject]
      before_action :set_execution, only: [:show, :approve, :reject]
      before_action :verify_reviewer!, only: [:approve, :reject]

      # GET /api/v1/bounty_reviews
      # List bounties awaiting your review
      def index
        bounties = Bounty.where(entity: current_entity)
                        .pending_human_review
        
        # Filter to only bounties this user can review
        reviewable = bounties.select { |b| b.can_be_reviewed_by?(current_user) }

        render json: {
          success: true,
          bounties: reviewable.map { |b| bounty_review_json(b) },
          count: reviewable.count,
          system_bounties: reviewable.count { |b| b.system_bounty? },
          user_bounties: reviewable.count { |b| !b.system_bounty? }
        }
      end

      # GET /api/v1/bounty_reviews/:id
      # Get details for reviewing a specific bounty
      def show
        unless @bounty.can_be_reviewed_by?(current_user)
          return render json: { 
            success: false, 
            error: "You don't have permission to review this bounty" 
          }, status: :forbidden
        end

        render json: {
          success: true,
          bounty: bounty_review_json(@bounty),
          execution: @execution&.to_api_response,
          ai_review: @bounty.ai_review_result,
          submission: {
            notes: @bounty.submission_notes,
            pr_url: @bounty.pr_url,
            work_url: @bounty.work_url,
            artifacts: @bounty.work_artifacts
          }
        }
      end

      # POST /api/v1/bounty_reviews/:id/approve
      # Approve the bounty submission
      def approve
        notes = params[:notes]
        final_points = params[:final_points]&.to_i
        quality_assessment = params[:quality_assessment]&.to_i

        # For external agent executions
        if @execution.present?
          result = @execution.human_approve!(
            reviewer: current_user,
            notes: notes,
            final_points: final_points
          )

          if result[:success]
            # Record the review and reward the reviewer
            review_record = record_review_reward!(
              decision: 'approved',
              notes: notes,
              quality_assessment: quality_assessment
            )

            render json: {
              success: true,
              message: "Bounty approved. #{result[:tokens_awarded]} tokens awarded to #{@bounty.claimed_by&.email || 'claimant'}.",
              tokens_awarded: result[:tokens_awarded],
              review_reward: {
                points_earned: review_record.review_points.to_f,
                message: "You earned #{review_record.review_points.round(1)} review points!"
              }
            }
          else
            render json: { success: false, error: result[:error] }, status: :unprocessable_entity
          end
        else
          # Regular bounty without external agent
          if @bounty.human_approve!(reviewer: current_user, notes: notes, final_points: final_points)
            # Record the review and reward
            review_record = record_review_reward!(
              decision: 'approved',
              notes: notes,
              quality_assessment: quality_assessment
            )

            render json: {
              success: true,
              message: "Bounty approved. #{@bounty.effective_points} points awarded.",
              points_awarded: @bounty.effective_points,
              review_reward: {
                points_earned: review_record.review_points.to_f,
                message: "You earned #{review_record.review_points.round(1)} review points!"
              }
            }
          else
            render json: { success: false, error: "Failed to approve bounty" }, status: :unprocessable_entity
          end
        end
      end

      # POST /api/v1/bounty_reviews/:id/reject
      # Reject the bounty submission
      def reject
        notes = params[:notes]
        quality_assessment = params[:quality_assessment]&.to_i
        
        if notes.blank?
          return render json: { 
            success: false, 
            error: "Rejection requires notes explaining why" 
          }, status: :unprocessable_entity
        end

        # For external agent executions
        if @execution.present?
          result = @execution.human_reject!(
            reviewer: current_user,
            notes: notes
          )

          if result[:success]
            # Record the review and reward
            review_record = record_review_reward!(
              decision: 'rejected',
              notes: notes,
              quality_assessment: quality_assessment
            )

            render json: {
              success: true,
              message: "Bounty rejected. The work has been declined and the bounty is available again.",
              review_reward: {
                points_earned: review_record.review_points.to_f,
                message: "You earned #{review_record.review_points.round(1)} review points!"
              }
            }
          else
            render json: { success: false, error: result[:error] }, status: :unprocessable_entity
          end
        else
          # Regular bounty without external agent
          if @bounty.human_reject!(reviewer: current_user, notes: notes)
            # Record the review and reward
            review_record = record_review_reward!(
              decision: 'rejected',
              notes: notes,
              quality_assessment: quality_assessment
            )

            render json: {
              success: true,
              message: "Bounty rejected. The bounty has been released for others to claim.",
              review_reward: {
                points_earned: review_record.review_points.to_f,
                message: "You earned #{review_record.review_points.round(1)} review points!"
              }
            }
          else
            render json: { success: false, error: "Failed to reject bounty" }, status: :unprocessable_entity
          end
        end
      end

      private

      def set_bounty
        @bounty = Bounty.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: "Bounty not found" }, status: :not_found
      end

      def set_execution
        @execution = ExternalAgentExecution.find_by(
          bounty: @bounty,
          awaiting_human_review: true
        )
      end

      def verify_reviewer!
        unless @bounty.can_be_reviewed_by?(current_user)
          render json: { 
            success: false, 
            error: reviewer_error_message
          }, status: :forbidden
        end
      end

      def reviewer_error_message
        if @bounty.system_bounty?
          "System bounties require admin review"
        elsif @bounty.user_funded?
          "Only the bounty funder or an admin can review this bounty"
        else
          "Only the bounty creator or an admin can review this bounty"
        end
      end

      def bounty_review_json(bounty)
        execution = ExternalAgentExecution.find_by(bounty: bounty, awaiting_human_review: true)
        
        {
          id: bounty.id,
          title: bounty.title,
          description: bounty.description&.truncate(300),
          bounty_type: bounty.bounty_type,
          points: bounty.points,
          status: bounty.status,
          
          # Funding info
          funding_source: bounty.funding_source,
          funded_by: bounty.funded_by&.email,
          funded_amount: bounty.funded_amount&.to_f,
          
          # Work info
          claimed_by: bounty.claimed_by&.email,
          submitted_at: bounty.submitted_at&.iso8601,
          pr_url: bounty.pr_url,
          work_url: bounty.work_url,
          requires_pr: bounty.requires_pr?,
          pr_merged: bounty.pr_merged?,
          
          # Review info
          ai_review_passed: bounty.ai_review_result&.dig('approved'),
          ai_review_score: bounty.ai_review_result&.dig('quality_score'),
          ai_feedback: bounty.ai_review_result&.dig('feedback'),
          
          # Review reward info
          review_reward_points: bounty.review_reward_points&.to_f || (bounty.points * 0.1).round(2),
          
          # External agent info
          external_agent: execution.present? ? {
            id: execution.external_agent_registration_id,
            name: execution.agent_name,
            platform: execution.agent_platform,
            tools_used: execution.tool_calls_count,
            quality_score: execution.quality_score&.to_f
          } : nil,
          
          # Review requirements
          is_system_bounty: bounty.system_bounty?,
          requires_admin: bounty.system_bounty?,
          reviewer_type: bounty.reviewer_type
        }
      end

      # Record review and calculate reward
      def record_review_reward!(decision:, notes:, quality_assessment:)
        BountyReview.record_review!(
          bounty: @bounty,
          reviewer: current_user,
          decision: decision,
          notes: notes,
          quality_assessment: quality_assessment
        )
      end
    end
  end
end
