module AmosAI
  class ConversationService
    attr_reader :user, :entity, :session_id

    def initialize(user:, entity:, session_id:)
      @user = user
      @entity = entity
      @session_id = session_id
    end

    # Main entry point for processing user messages
    def process_message(message)
      start_time = Time.current

      begin
        # Store user message
        user_conversation = store_message(content: message, message_type: "user")

        # Get conversation context
        conversation_history = get_conversation_context

        # Process with main conversation engine
        ai_response = conversation_engine.process(
          message: message,
          history: conversation_history,
          business_context: get_business_context
        )

        # Store AI response
        assistant_conversation = store_message(
          content: ai_response[:content],
          message_type: "assistant",
          metadata: {
            model_used: ai_response[:model],
            tokens_used: ai_response[:tokens],
            confidence: ai_response[:confidence]
          }
        )

        # Trigger background intelligence processing
        process_background_intelligence(user_conversation, ai_response)

        # Log performance
        log_activity(
          agent_name: "conversation_engine",
          activity_type: "message_processing",
          input_data: { message: message },
          output_data: ai_response,
          processing_time_ms: ((Time.current - start_time) * 1000).round,
          conversation: user_conversation
        )

        # Return response with any suggested actions
        {
          success: true,
          response: ai_response[:content],
          action: ai_response[:suggested_action],
          payload: ai_response[:action_payload],
          session_id: @session_id
        }

      rescue => e
        Rails.logger.error "Scout AI Conversation Error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")

        # Log error activity
        log_activity(
          agent_name: "conversation_engine",
          activity_type: "error_handling",
          input_data: { message: message, error: e.message },
          output_data: { error: true },
          processing_time_ms: ((Time.current - start_time) * 1000).round,
          conversation: user_conversation
        )

        # Return fallback response
        {
          success: false,
          response: "I apologize, but I'm having trouble processing your message right now. Please try again.",
          action: nil,
          payload: nil,
          session_id: @session_id
        }
      end
    end

    private

    def conversation_engine
      @conversation_engine ||= ScoutAI::ConversationEngine.new(
        user: @user,
        entity: @entity
      )
    end

    def intent_analyzer
      @intent_analyzer ||= ScoutAI::IntentAnalyzer.new(
        user: @user,
        entity: @entity
      )
    end

    def business_extractor
      @business_extractor ||= ScoutAI::BusinessExtractor.new(
        user: @user,
        entity: @entity
      )
    end

    def store_message(content:, message_type:, metadata: {})
      ScoutConversation.create!(
        user: @user,
        entity: @entity,
        session_id: @session_id,
        message_type: message_type,
        content: content,
        metadata: metadata
      )
    end

    def get_conversation_context(limit: 20)
      ScoutConversation.session_history(@session_id, limit: limit)
                      .map(&:to_ai_message)
    end

    def get_business_context
      biz = BusinessContext.for(@user, @entity)

      {
        entity_name: biz.company_name,
        industry: biz.industry,
        business_profile: biz.profile,
        recent_campaigns: @user.campaigns.where(entity_id: @entity.id).recent.limit(3),
        recent_landing_pages: @user.landing_pages.where(entity_id: @entity.id).recent.limit(3),
        insights: BusinessInsight.where(entity_id: @entity.id).high_confidence.recent.limit(10)
      }
    end

    def process_background_intelligence(conversation, ai_response)
      # Process in background to avoid blocking response
      ProcessBackgroundIntelligenceJob.perform_later(
        conversation_id: conversation.id,
        ai_response: ai_response
      )
    end

    def log_activity(agent_name:, activity_type:, input_data:, output_data:, processing_time_ms:, conversation:)
      AgentActivity.create!(
        conversation: conversation,
        agent_name: agent_name,
        activity_type: activity_type,
        input_data: input_data,
        output_data: output_data,
        processing_time_ms: processing_time_ms
      )
    rescue => e
      Rails.logger.error "Failed to log agent activity: #{e.message}"
    end
  end
end
