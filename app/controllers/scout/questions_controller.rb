# frozen_string_literal: true

module Scout
  class QuestionsController < ApplicationController
    # Skip ApplicationController's Devise auth for mobile API endpoints - we use custom dual auth
    skip_before_action :authenticate_user!, only: [:pending, :answer, :skip]
    skip_before_action :check_subscription_status, only: [:pending, :answer, :skip, :broadcast_question, :broadcast_completion], raise: false
    skip_before_action :check_onboarding_status, only: [:pending, :answer, :skip, :broadcast_question, :broadcast_completion], raise: false

    before_action :authenticate_user_or_api!, except: [:broadcast_question, :broadcast_completion]
    before_action :set_question, only: [:answer, :skip]

    # Skip CSRF for API and internal worker-to-web callbacks
    skip_before_action :verify_authenticity_token, only: [:broadcast_question, :broadcast_completion, :pending, :answer, :skip]

    # GET /scout/questions/pending
    def pending
      # Get pending questions for this user's session
      session_id = params[:session_id] || session[:scout_session_id]
      
      questions = AgentInputRequest.joins(agent_plugin_execution: :user)
                                   .where(agent_plugin_executions: { user_id: current_user.id })
                                   .active
                                   .by_priority

      # Filter by session if provided
      if session_id.present?
        questions = questions.for_session(session_id)
      end

      render json: {
        success: true,
        questions: questions.map(&:as_queue_json),
        count: questions.count
      }
    end

    # POST /scout/questions/:id/answer
    def answer
      answer_content = params[:answer]
      attachment = params[:attachment]
      
      # Allow empty answer if there's an attachment
      if answer_content.blank? && attachment.blank?
        render json: { success: false, error: "Answer cannot be empty" }, status: :unprocessable_entity
        return
      end

      # Handle attachment if present
      attachment_info = nil
      if attachment.present?
        attachment_info = process_answer_attachment(attachment)
        Rails.logger.info "📎 Answer includes attachment: #{attachment_info[:filename]}"
      end

      # Build the full answer with attachment reference
      full_answer = answer_content.to_s
      if attachment_info
        full_answer += "\n\n[Attached: #{attachment_info[:filename]}]"
        full_answer += "\n[Attachment URL: #{attachment_info[:url]}]" if attachment_info[:url]
      end

      @question.answer!(full_answer, attachment: attachment_info)
      
      Rails.logger.info "✅ User #{current_user.id} answered question #{@question.id}"
      
      render json: {
        success: true,
        message: "Answer submitted",
        question_id: @question.id,
        has_attachment: attachment_info.present?
      }
    rescue => e
      Rails.logger.error "Failed to answer question #{@question.id}: #{e.message}"
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end

    # POST /scout/questions/:id/skip
    def skip
      reason = params[:reason]
      
      @question.skip!(reason: reason)
      
      Rails.logger.info "⏭️ User #{current_user.id} skipped question #{@question.id}"
      
      render json: {
        success: true,
        message: "Question skipped",
        question_id: @question.id
      }
    rescue => e
      Rails.logger.error "Failed to skip question #{@question.id}: #{e.message}"
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end

    # POST /scout/broadcast_question
    # Internal endpoint for workers to trigger ActionCable broadcasts
    # This bypasses the cross-process ActionCable/Redis issue
    def broadcast_question
      session_id = params[:session_id]
      question_data = params[:question]
      pending_count = params[:pending_count]
      
      Rails.logger.info "📡 [BroadcastQuestion] Received callback for session #{session_id}"
      Rails.logger.info "📡 [BroadcastQuestion] Question: #{question_data[:id]} from #{question_data[:agent_name]}"
      
      unless session_id.present? && question_data.present?
        render json: { success: false, error: "Missing session_id or question data" }, status: :bad_request
        return
      end
      
      # Convert question_data to a regular hash if it's ActionController::Parameters
      question_hash = case question_data
                      when ActionController::Parameters
                        question_data.permit!.to_h
                      when Hash
                        question_data
                      else
                        question_data.to_h
                      end
      
      # Broadcast via ActionCable from the web process (this works!)
      ScoutChannel.broadcast_to(session_id, {
        type: 'question_queue_update',
        action: 'added',
        question: question_hash,
        pending_count: pending_count || 1
      })
      
      Rails.logger.info "📡 [BroadcastQuestion] ✅ Broadcasted question_queue_update via ActionCable"
      
      render json: { success: true, message: "Broadcast sent" }
    rescue => e
      Rails.logger.error "📡 [BroadcastQuestion] ❌ Failed: #{e.message}"
      render json: { success: false, error: e.message }, status: :internal_server_error
    end
    
    # POST /scout/broadcast_completion
    # Internal endpoint for workers to trigger completion broadcasts
    def broadcast_completion
      session_id = params[:session_id]
      completion_data = params[:completion]
      
      Rails.logger.info "📡 [BroadcastCompletion] Received callback for session #{session_id}"
      Rails.logger.info "📡 [BroadcastCompletion] Agent: #{completion_data[:agent_name]}"
      
      unless session_id.present? && completion_data.present?
        render json: { success: false, error: "Missing session_id or completion data" }, status: :bad_request
        return
      end
      
      # Convert completion_data to a regular hash if it's ActionController::Parameters
      completion_hash = case completion_data
                        when ActionController::Parameters
                          completion_data.permit!.to_h
                        when Hash
                          completion_data
                        else
                          completion_data.to_h
                        end
      
      # Broadcast completion to question queue overlay
      ScoutChannel.broadcast_to(session_id, {
        type: 'question_queue_update',
        action: 'completed',
        completion: completion_hash
      })
      
      # Broadcast work item notification to trigger inbox refresh
      ScoutChannel.broadcast_to(session_id, {
        type: 'work_item_notification',
        agent_name: completion_hash['agent_name'] || completion_hash[:agent_name],
        status: 'completed',
        summary: completion_hash['message'] || completion_hash[:message],
        execution_id: completion_hash['execution_id'] || completion_hash[:execution_id]
      })
      
      Rails.logger.info "📡 [BroadcastCompletion] ✅ Broadcasted completion via ActionCable"
      
      render json: { success: true, message: "Broadcast sent" }
    rescue => e
      Rails.logger.error "📡 [BroadcastCompletion] ❌ Failed: #{e.message}"
      render json: { success: false, error: e.message }, status: :internal_server_error
    end

    private

    def set_question
      @question = AgentInputRequest.find(params[:id])
      
      # Verify ownership
      unless @question.agent_plugin_execution.user_id == current_user.id
        render json: { success: false, error: "Unauthorized" }, status: :forbidden
      end
    end

    def process_answer_attachment(attachment)
      return nil unless attachment.is_a?(ActionDispatch::Http::UploadedFile)

      # Store the attachment using Active Storage
      blob = ActiveStorage::Blob.create_and_upload!(
        io: attachment.tempfile,
        filename: attachment.original_filename,
        content_type: attachment.content_type
      )

      # Return attachment info
      {
        filename: attachment.original_filename,
        content_type: attachment.content_type,
        size: attachment.size,
        blob_id: blob.id,
        url: Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
      }
    rescue => e
      Rails.logger.error "Failed to process attachment: #{e.message}"
      nil
    end

    # Support both session auth (web) and Bearer token auth (mobile)
    def authenticate_user_or_api!
      auth_header = request.headers["Authorization"]
      token = auth_header&.gsub(/^Bearer /, "")

      Rails.logger.info "🔐 [Questions] Auth header: #{auth_header.present? ? auth_header.first(20) : 'MISSING'}"
      Rails.logger.info "🔐 [Questions] Token: #{token.present? ? token.first(8) + '...' : 'MISSING'}"

      if token.present?
        # Mobile API request with Bearer token
        @current_user = User.find_by(api_key: token)
        Rails.logger.info "🔐 [Questions] User found: #{@current_user&.email || 'NOT FOUND'}"
        unless @current_user
          render json: { error: "Invalid token" }, status: :unauthorized
          return
        end
      else
        # Web request - use Devise session auth
        Rails.logger.info "🔐 [Questions] Falling back to Devise auth"
        authenticate_user!
      end
    end

    def current_user
      @current_user || super
    end
  end
end

