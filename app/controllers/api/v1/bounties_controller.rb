# frozen_string_literal: true

module Api
  module V1
    # BountiesController - API for bounties including user-funded bounties
    #
    # Users can:
    # - View available bounties
    # - Create their own bounties funded from their AMOS token balance
    # - View bounties they've funded or created
    # - Cancel unfilled bounties and get refunded
    #
    class BountiesController < Api::V1::BaseController
      before_action :set_bounty, only: [:show, :cancel]

      # GET /api/v1/bounties
      # List available bounties
      def index
        bounties = Bounty.where(entity: current_entity).available

        # Optional filters
        bounties = bounties.by_type(params[:type]) if params[:type].present?
        bounties = bounties.where('points >= ?', params[:min_points]) if params[:min_points].present?
        bounties = bounties.where('points <= ?', params[:max_points]) if params[:max_points].present?
        
        if params[:funding_source].present?
          bounties = bounties.where(funding_source: params[:funding_source])
        end

        bounties = bounties.order(urgency_score: :desc, points: :desc).limit(50)

        render json: {
          success: true,
          bounties: bounties.map { |b| bounty_json(b) },
          count: bounties.count
        }
      end

      # GET /api/v1/bounties/:id
      def show
        render json: {
          success: true,
          bounty: bounty_json(@bounty, detailed: true)
        }
      end

      # POST /api/v1/bounties
      # Create a user-funded bounty
      def create
        # Validate required params
        required = [:title, :description, :bounty_type, :points]
        missing = required.select { |p| params[p].blank? }
        if missing.any?
          return render json: { 
            success: false, 
            error: "Missing required fields: #{missing.join(', ')}" 
          }, status: :unprocessable_entity
        end

        points = params[:points].to_i
        
        # Check user's available balance
        available = BountyEscrowService.available_balance(current_user)
        if available < points
          return render json: {
            success: false,
            error: "Insufficient AMOS balance. Available: #{available.round(2)}, Required: #{points}",
            available_balance: available.round(2)
          }, status: :unprocessable_entity
        end

        begin
          bounty = Bounty.create_user_funded!(
            entity: current_entity,
            created_by: current_user,
            title: params[:title],
            description: params[:description],
            bounty_type: params[:bounty_type],
            points: points,
            requires_pr: params[:requires_pr] == true || params[:requires_pr] == 'true',
            target_repo: params[:target_repo],
            target_branch: params[:target_branch] || 'main',
            expires_in: (params[:expires_in_days]&.to_i || 30).days,
            metadata: params[:metadata] || {}
          )

          render json: {
            success: true,
            bounty: bounty_json(bounty),
            message: "Bounty created! #{points} AMOS tokens have been escrowed from your balance.",
            escrowed_amount: points,
            remaining_balance: BountyEscrowService.available_balance(current_user).round(2)
          }, status: :created
        rescue Bounty::InsufficientBalanceError => e
          render json: { success: false, error: e.message }, status: :unprocessable_entity
        rescue => e
          Rails.logger.error "[Bounties] Create failed: #{e.message}"
          render json: { success: false, error: "Failed to create bounty: #{e.message}" }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/bounties/my_funded
      # Bounties the current user is funding
      def my_funded
        bounties = Bounty.where(funded_by: current_user)
                        .order(created_at: :desc)
                        .limit(100)

        render json: {
          success: true,
          bounties: bounties.map { |b| bounty_json(b) },
          count: bounties.count,
          total_escrowed: bounties.escrowed.sum(:funded_amount).to_f,
          total_released: bounties.where(escrow_status: 'released').sum(:funded_amount).to_f
        }
      end

      # GET /api/v1/bounties/my_created
      # Bounties the current user created (funded or not)
      def my_created
        bounties = Bounty.where(created_by: current_user)
                        .order(created_at: :desc)
                        .limit(100)

        render json: {
          success: true,
          bounties: bounties.map { |b| bounty_json(b) },
          count: bounties.count
        }
      end

      # POST /api/v1/bounties/:id/cancel
      # Cancel an unfilled bounty and refund escrow
      def cancel
        unless @bounty.funded_by == current_user || current_user.admin?
          return render json: { 
            success: false, 
            error: "Only the funder or an admin can cancel this bounty" 
          }, status: :forbidden
        end

        unless @bounty.status == 'open'
          return render json: { 
            success: false, 
            error: "Can only cancel open bounties (current status: #{@bounty.status})" 
          }, status: :unprocessable_entity
        end

        reason = params[:reason] || "Cancelled by funder"
        refund_amount = @bounty.funded_amount || 0

        begin
          @bounty.cancel!(reason: reason)
          @bounty.refund_escrow! if @bounty.escrowed?

          render json: {
            success: true,
            message: "Bounty cancelled. #{refund_amount} AMOS tokens have been refunded.",
            refunded_amount: refund_amount.to_f,
            new_balance: BountyEscrowService.available_balance(current_user).round(2)
          }
        rescue => e
          render json: { success: false, error: "Failed to cancel: #{e.message}" }, status: :unprocessable_entity
        end
      end

      private

      def set_bounty
        @bounty = Bounty.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: "Bounty not found" }, status: :not_found
      end

      def bounty_json(bounty, detailed: false)
        json = {
          id: bounty.id,
          title: bounty.title,
          description: detailed ? bounty.description : bounty.description&.truncate(200),
          bounty_type: bounty.bounty_type,
          points: bounty.points,
          status: bounty.status,
          source: bounty.source,
          
          # Funding
          funding_source: bounty.funding_source,
          user_funded: bounty.user_funded?,
          funded_by: bounty.funded_by&.email,
          funded_amount: bounty.funded_amount&.to_f,
          escrow_status: bounty.escrow_status,
          
          # Requirements
          requires_pr: bounty.requires_pr?,
          target_repo: bounty.target_repo,
          requires_human_review: bounty.requires_human_review?,
          
          # Scores
          urgency_score: bounty.urgency_score,
          impact_score: bounty.impact_score,
          
          # Timestamps
          created_at: bounty.created_at.iso8601,
          expires_at: bounty.expires_at&.iso8601,
          
          # Claim info
          claimed_by: bounty.claimed_by&.email,
          claimed_at: bounty.claimed_at&.iso8601
        }

        if detailed
          json.merge!(
            ai_scoring_rationale: bounty.ai_scoring_rationale,
            submission_notes: bounty.submission_notes,
            pr_url: bounty.pr_url,
            work_url: bounty.work_url,
            created_by: bounty.created_by&.email,
            reviewed_by: bounty.reviewed_by&.email,
            review_notes: bounty.review_notes,
            final_points: bounty.final_points,
            metadata: bounty.metadata
          )
        end

        json
      end
    end
  end
end
