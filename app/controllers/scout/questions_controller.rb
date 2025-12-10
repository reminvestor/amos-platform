# frozen_string_literal: true

module Scout
  class QuestionsController < ApplicationController
    before_action :authenticate_user!, except: [:broadcast_question]
    before_action :set_question, only: [:answer, :skip]
    
    # Skip CSRF for internal worker-to-web callbacks
    skip_before_action :verify_authenticity_token, only: [:broadcast_question, :broadcast_completion]

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

      # Build the full answer with attachment reference and vision analysis
      full_answer = answer_content.to_s
      if attachment_info
        full_answer += "\n\n[Attached: #{attachment_info[:filename]}]"
        full_answer += "\n[Attachment URL: #{attachment_info[:url]}]" if attachment_info[:url]
        
        # Include vision analysis so the agent can understand image content
        if attachment_info[:vision_analysis].present?
          full_answer += "\n\n📷 **Image Analysis:**\n#{attachment_info[:vision_analysis]}"
          Rails.logger.info "📎 Including vision analysis in answer to agent"
        end
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
      # Agent communication attachments are ALWAYS transient (short-term)
      # They don't need to be saved to the knowledge base - just for this conversation
      blob = ActiveStorage::Blob.create_and_upload!(
        io: attachment.tempfile,
        filename: attachment.original_filename,
        content_type: attachment.content_type,
        metadata: {
          transient: true,
          storage_type: 'short-term',
          expires_at: 24.hours.from_now.iso8601,
          source: 'agent_communication'
        }
      )

      Rails.logger.info "📎 Agent communication attachment stored as transient (24hr expiry)"

      result = {
        filename: attachment.original_filename,
        content_type: attachment.content_type,
        size: attachment.size,
        blob_id: blob.id,
        url: Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true),
        transient: true
      }

      # For images, run vision analysis so the agent can understand the content
      if image_file?(attachment)
        Rails.logger.info "👁️ Running vision analysis on image attachment for agent"
        begin
          # Read the image and convert to base64
          attachment.tempfile.rewind
          image_data = Base64.strict_encode64(attachment.tempfile.read)
          
          # Use Bedrock vision to analyze the image
          bedrock = BedrockService.new
          analysis = bedrock.send_message_with_image(
            "Analyze this image and describe what you see in detail. This is being provided as context for an AI agent to help complete a task. Include: visual elements, text content (if any), layout, colors, style, and any other relevant details.",
            image_data,
            attachment.content_type
          )
          
          result[:vision_analysis] = analysis
          result[:content_description] = analysis
          Rails.logger.info "✅ Vision analysis complete for #{attachment.original_filename}"
        rescue => vision_error
          Rails.logger.error "Vision analysis failed: #{vision_error.message}"
          result[:vision_analysis] = "Image uploaded but vision analysis unavailable"
        end
      end

      result
    rescue => e
      Rails.logger.error "Failed to process attachment: #{e.message}"
      nil
    end

    def image_file?(file)
      %w[image/jpeg image/jpg image/png image/gif image/webp].include?(file.content_type)
    end
  end
end

