# frozen_string_literal: true

module Api
  module V1
    # Tool Confirmations Controller
    # Handles user confirmation/denial of sensitive tool actions
    # Part of CaMeL-style prompt injection mitigation
    class ToolConfirmationsController < BaseController
      before_action :set_pending_confirmation, only: [:confirm, :deny, :show]

      # GET /api/v1/tool_confirmations/:id
      # Get status of a pending confirmation
      def show
        render json: {
          confirmation_id: @pending.confirmation_id,
          tool_name: @pending.tool_name,
          action_description: @pending.action_description,
          status: @pending.status,
          expires_at: @pending.expires_at,
          expired: @pending.expired?
        }
      end

      # GET /api/v1/tool_confirmations
      # List pending confirmations for current session
      def index
        session_id = params[:session_id]
        
        confirmations = PendingToolConfirmation
          .where(entity: current_entity, user: current_user)
          .pending
          .not_expired
          .order(created_at: :desc)
        
        confirmations = confirmations.for_session(session_id) if session_id.present?
        
        render json: {
          confirmations: confirmations.map { |c| serialize_confirmation(c) }
        }
      end

      # POST /api/v1/tool_confirmations/confirm
      # User confirms the pending action
      def confirm
        if @pending.expired?
          return render json: { success: false, error: 'Confirmation expired' }, status: :gone
        end

        unless @pending.pending?
          return render json: { 
            success: false, 
            error: "Action already #{@pending.status}" 
          }, status: :unprocessable_entity
        end

        # Mark as confirmed
        @pending.confirm!

        # Record the confirmation for caching
        ToolPolicyService.record_confirmation(
          entity: @pending.entity,
          user: @pending.user,
          tool_name: @pending.tool_name,
          args: @pending.tool_args
        )

        # Execute the tool
        result = execute_confirmed_tool

        render json: {
          success: true,
          message: 'Action confirmed and executed',
          tool_result: result
        }
      rescue => e
        Rails.logger.error "[ToolConfirmations] Error executing confirmed action: #{e.message}"
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      # POST /api/v1/tool_confirmations/deny
      # User denies the pending action
      def deny
        if @pending.expired?
          return render json: { success: false, error: 'Confirmation expired' }, status: :gone
        end

        unless @pending.pending?
          return render json: { 
            success: false, 
            error: "Action already #{@pending.status}" 
          }, status: :unprocessable_entity
        end

        @pending.deny!

        # Log the denial
        Rails.logger.info "[ToolConfirmations] Denied: #{@pending.tool_name} by user #{@pending.user_id}"

        render json: {
          success: true,
          message: 'Action denied'
        }
      end

      # DELETE /api/v1/tool_confirmations/expire_all
      # Clean up expired confirmations
      def expire_all
        count = PendingToolConfirmation
          .where(entity: current_entity)
          .where('expires_at < ?', Time.current)
          .where(status: 'pending')
          .update_all(status: 'expired', resolved_at: Time.current)

        render json: { success: true, expired_count: count }
      end

      private

      def set_pending_confirmation
        confirmation_id = params[:confirmation_id] || params[:id]
        
        @pending = PendingToolConfirmation.find_by(
          confirmation_id: confirmation_id,
          entity: current_entity,
          user: current_user
        )

        unless @pending
          render json: { success: false, error: 'Confirmation not found' }, status: :not_found
        end
      end

      def execute_confirmed_tool
        # Build a tool service to execute
        tool_service = ScoutGenericToolsServiceV2.new(
          @pending.user,
          @pending.entity,
          @pending.session_id
        )

        # Execute the tool
        result = tool_service.execute_tool_by_name(
          @pending.tool_name,
          @pending.tool_args.symbolize_keys
        )

        # Broadcast the result via ScoutChannel if we have a session
        if @pending.session_id.present? && defined?(ScoutChannel)
          ScoutChannel.broadcast_to(@pending.session_id, {
            type: 'tool_result',
            tool_name: @pending.tool_name,
            success: result[:success],
            result: result.except(:raw_data) # Don't send huge raw data
          })
        end

        result
      end

      def serialize_confirmation(confirmation)
        {
          confirmation_id: confirmation.confirmation_id,
          tool_name: confirmation.tool_name,
          action_description: confirmation.action_description,
          reason: confirmation.reason,
          status: confirmation.status,
          created_at: confirmation.created_at,
          expires_at: confirmation.expires_at,
          time_remaining: [(confirmation.expires_at - Time.current).to_i, 0].max
        }
      end
    end
  end
end
