class VoiceImmediateProcessor
  IMMEDIATE_RESPONSE_TEMPLATES = {
    analysis: [
      "I'll analyze that for you right away.",
      "Let me look into that data for you.",
      "I'm pulling up that analysis now."
    ],
    campaign: [
      "I'll prepare your campaign details.",
      "Let me fetch those campaigns for you.",
      "I'm gathering your campaign information."
    ],
    meeting: [
      "I'll check the calendar and schedule that.",
      "Let me find the best time for that meeting.",
      "I'm scheduling that for you now."
    ],
    search: [
      "I'm searching for that information.",
      "Let me find that for you.",
      "I'll locate that right away."
    ],
    default: [
      "I'm on it.",
      "Working on that for you.",
      "Let me handle that.",
      "I'll take care of that right away."
    ]
  }.freeze

  def initialize(task_session)
    @task = task_session
    @start_time = Time.current
  end

  def process!
    # Goal: Complete within 300ms, leaving 200ms for network/TTS
    
    # 1. Get task description and detect intent (50ms budget)
    intent = detect_intent
    
    # 2. Generate immediate response (100ms budget)
    response = generate_immediate_response(intent)
    
    # 3. Broadcast via ActionCable (50ms budget)
    broadcast_response(response)
    
    # 4. Log performance
    log_performance
    
    response
  rescue => e
    Rails.logger.error "Voice immediate processing failed: #{e.message}"
    fallback_response
  end

  private

  def detect_intent
    description = @task.metadata['description'].to_s.downcase
    
    # Simple keyword matching for speed (no LLM call)
    return :analysis if description.match?(/analyz|report|metric|data/)
    return :campaign if description.match?(/campaign|email|marketing/)
    return :meeting if description.match?(/meeting|schedule|calendar|book/)
    return :search if description.match?(/find|search|look|where/)
    
    :default
  end

  def generate_immediate_response(intent)
    # Check if we have a pre-generated response
    if @task.metadata['immediate_response'].present?
      return @task.metadata['immediate_response']
    end
    
    # Otherwise use template
    templates = IMMEDIATE_RESPONSE_TEMPLATES[intent]
    selected = templates.sample
    
    # Add contextual details if available quickly
    if @task.metadata['entity_name']
      selected += " for #{@task.metadata['entity_name']}"
    end
    
    selected
  end

  def broadcast_response(response)
    # Find parent conversation
    if @task.parent_conversation_id.present?
      # Get voice session from parent conversation
      voice_session = VoiceSession.find_by(session_id: @task.parent_conversation_id)
      
      if voice_session
        # Broadcast immediate response
        VoiceChannel.broadcast_to(
          voice_session,
          {
            type: 'immediate_response',
            content: response,
            task_id: @task.id,
            should_synthesize: true,
            timestamp: Time.current.iso8601
          }
        )
        
        # Also save to conversation history
        ScoutConversation.create!(
          user: @task.user,
          entity_id: @task.user.entity_id,
          session_id: @task.parent_conversation_id,
          message_type: 'assistant',
          content: response,
          metadata: {
            task_id: @task.id,
            response_type: 'immediate',
            processing_time_ms: (Time.current - @start_time) * 1000
          }
        )
      end
    end
  end

  def log_performance
    processing_time_ms = (Time.current - @start_time) * 1000
    
    Rails.logger.info({
      event: 'voice_immediate_processed',
      task_id: @task.id,
      processing_time_ms: processing_time_ms,
      under_target: processing_time_ms < 300
    }.to_json)
    
    # Update task metadata
    @task.update!(
      metadata: @task.metadata.merge(
        immediate_processing_time_ms: processing_time_ms
      )
    )
  end

  def fallback_response
    "I'm working on that for you."
  end
end
