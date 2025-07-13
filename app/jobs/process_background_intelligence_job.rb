class ProcessBackgroundIntelligenceJob < ApplicationJob
  queue_as :scout_ai
  
  def perform(conversation_id:, ai_response:)
    conversation = ScoutConversation.find(conversation_id)
    user = conversation.user
    entity = conversation.entity
    
    Rails.logger.info "Processing background intelligence for conversation #{conversation_id}"
    
    # Run intent analysis
    analyze_intent(conversation, user, entity, ai_response)
    
    # Run business intelligence extraction
    extract_business_intelligence(conversation, user, entity)
    
  rescue => e
    Rails.logger.error "Background intelligence processing failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end
  
  private
  
  def analyze_intent(conversation, user, entity, ai_response)
    start_time = Time.current
    
    begin
      intent_analyzer = ScoutAI::IntentAnalyzer.new(user: user, entity: entity)
      
      # Get recent conversation context
      recent_messages = ScoutConversation.for_session(conversation.session_id)
                                        .order(created_at: :desc)
                                        .limit(5)
                                        .map { |msg| "#{msg.message_type}: #{msg.content}" }
                                        .reverse
                                        .join("\n")
      
      intent_result = intent_analyzer.analyze(
        conversation_context: recent_messages,
        ai_response: ai_response[:content]
      )
      
      # Log the activity
      AgentActivity.create!(
        conversation: conversation,
        agent_name: 'intent_analyzer',
        activity_type: 'intent_analysis',
        input_data: { 
          context: recent_messages,
          ai_response: ai_response[:content]
        },
        output_data: intent_result,
        processing_time_ms: ((Time.current - start_time) * 1000).round
      )
      
      Rails.logger.info "Intent analysis completed: #{intent_result[:suggested_template]}"
      
    rescue => e
      Rails.logger.error "Intent analysis failed: #{e.message}"
      
      # Log the error
      AgentActivity.create!(
        conversation: conversation,
        agent_name: 'intent_analyzer',
        activity_type: 'error_handling',
        input_data: { error: e.message },
        output_data: { success: false },
        processing_time_ms: ((Time.current - start_time) * 1000).round
      )
    end
  end
  
  def extract_business_intelligence(conversation, user, entity)
    start_time = Time.current
    
    begin
      business_extractor = ScoutAI::BusinessExtractor.new(user: user, entity: entity)
      
      # Get recent conversation context
      recent_messages = ScoutConversation.for_session(conversation.session_id)
                                        .order(created_at: :desc)
                                        .limit(10)
                                        .map { |msg| "#{msg.message_type}: #{msg.content}" }
                                        .reverse
                                        .join("\n")
      
      extraction_result = business_extractor.extract(conversation_context: recent_messages)
      
      # Store any high-confidence insights
      if extraction_result[:insights]&.any?
        extraction_result[:insights].each do |insight|
          if insight[:confidence] >= 0.7
            BusinessInsight.create!(
              entity: entity,
              source_conversation: conversation,
              insight_type: insight[:type],
              content: insight[:content],
              confidence_score: insight[:confidence]
            )
          end
        end
      end
      
      # Log the activity
      AgentActivity.create!(
        conversation: conversation,
        agent_name: 'business_extractor',
        activity_type: 'business_extraction',
        input_data: { context: recent_messages },
        output_data: extraction_result,
        processing_time_ms: ((Time.current - start_time) * 1000).round
      )
      
      Rails.logger.info "Business extraction completed: #{extraction_result[:insights]&.count || 0} insights found"
      
    rescue => e
      Rails.logger.error "Business extraction failed: #{e.message}"
      
      # Log the error
      AgentActivity.create!(
        conversation: conversation,
        agent_name: 'business_extractor',
        activity_type: 'error_handling',
        input_data: { error: e.message },
        output_data: { success: false },
        processing_time_ms: ((Time.current - start_time) * 1000).round
      )
    end
  end
end 