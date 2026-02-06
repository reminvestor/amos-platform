class VoiceFollowupJob < ApplicationJob
  include JobErrorHandling
  
  queue_as :critical # High priority for voice responses
  
  def perform(task_session_id)
    @task = TaskSession.find(task_session_id)
    @voice_session = find_voice_session
    
    return unless @voice_session # Safety check
    
    begin
      # Update task status
      @task.update!(
        status: 'active',
        started_at: Time.current,
        progress: 10
      )
      
      # Broadcast that we're processing
      broadcast_status('processing', 'Working on your request...')
      
      # Execute the task with appropriate model
      result = execute_voice_task
      
      # Synthesize and broadcast the response
      broadcast_voice_response(result[:response])
      
      # Mark as completed
      @task.update!(
        status: 'completed',
        progress: 100,
        state: @task.state.merge(result: result)
      )
      
    rescue => e
      handle_voice_error(e)
    end
  end
  
  private
  
  def find_voice_session
    return nil unless @task.parent_conversation_id.present?
    VoiceSession.find_by(session_id: @task.parent_conversation_id)
  end
  
  def execute_voice_task
    # V3: Execute via agent loop
    agent = V3::AgentLoop.new(
      user: @task.user,
      entity: @task.entity,
      session_id: @task.parent_conversation_id || SecureRandom.uuid,
      model: ENV.fetch("BEDROCK_VOICE_MODEL", "anthropic.claude-sonnet-4-v1")
    )

    prompt = @task.metadata&.dig("description") || @task.metadata&.dig("prompt") || "Execute the pending task"
    result = agent.process_message_streaming(prompt, ->(_) {}, [])
    result.dig(:final_response, :message)
  end
  
  def broadcast_voice_response(response)
    return unless @voice_session && response.present?
    
    # Clean up response for voice
    voice_response = prepare_voice_response(response)
    
    # Broadcast via voice channel
    VoiceChannel.broadcast_to(
      @voice_session,
      {
        type: 'followup_response',
        content: voice_response,
        task_id: @task.id,
        should_synthesize: true,
        priority: 'high', # Higher priority for TTS queue
        timestamp: Time.current.iso8601
      }
    )
    
    # Also save to conversation history
    ScoutConversation.create!(
      user: @task.user,
      entity_id: @task.user.entity_id,
      session_id: @task.parent_conversation_id,
      message_type: 'assistant',
      content: voice_response,
      metadata: {
        task_id: @task.id,
        response_type: 'voice_followup',
        processing_time_ms: (Time.current - @task.started_at) * 1000
      }
    )
  end
  
  def broadcast_status(status, message = nil)
    return unless @voice_session
    
    VoiceChannel.broadcast_to(
      @voice_session,
      {
        type: 'task_status',
        task_id: @task.id,
        status: status,
        message: message,
        timestamp: Time.current.iso8601
      }
    )
  end
  
  def prepare_voice_response(response)
    # Clean up response for natural voice synthesis
    cleaned = response.dup
    
    # Remove markdown formatting
    cleaned.gsub!(/\*\*(.+?)\*\*/, '\1') # Bold
    cleaned.gsub!(/\*(.+?)\*/, '\1')     # Italic
    cleaned.gsub!(/`(.+?)`/, '\1')       # Code
    cleaned.gsub!(/^#+\s+/, '')           # Headers
    
    # Simplify lists for voice
    cleaned.gsub!(/^[-*]\s+/, '• ')      # Bullet points
    cleaned.gsub!(/^\d+\.\s+/, '')        # Numbered lists
    
    # Add natural pauses
    cleaned.gsub!(/\.\s+/, '. ')         # After sentences
    cleaned.gsub!(/,\s+/, ', ')          # After commas
    cleaned.gsub!(/:\s+/, ': ')          # After colons
    
    # Break up long sentences
    sentences = cleaned.split(/\.\s+/)
    if sentences.any? { |s| s.split.length > 25 }
      sentences = sentences.map do |sentence|
        if sentence.split.length > 25
          # Insert natural break points
          words = sentence.split
          midpoint = words.length / 2
          words.insert(midpoint, ',')
          words.join(' ')
        else
          sentence
        end
      end
      cleaned = sentences.join('. ')
    end
    
    # Limit response length for voice (TTS has limits)
    if cleaned.length > 3000
      cleaned = cleaned[0..2900] + "... I've prepared the complete details in the chat for you to review."
    end
    
    cleaned.strip
  end
  
  def handle_voice_error(error)
    Rails.logger.error "Voice followup task #{@task.id} failed: #{error.message}"
    Rails.logger.error error.backtrace.first(5).join("\n")
    
    # Update task status
    @task.update!(
      status: 'failed',
      state: @task.state.merge(
        error: error.message,
        failed_at: Time.current
      )
    )
    
    # Broadcast error in a user-friendly way
    if @voice_session
      VoiceChannel.broadcast_to(
        @voice_session,
        {
          type: 'task_error',
          task_id: @task.id,
          content: "I encountered an issue processing that request. Please try asking again.",
          should_synthesize: true,
          timestamp: Time.current.iso8601
        }
      )
    end
  end
end
