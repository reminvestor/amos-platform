# VoiceAgentService processes voice transcripts through Scout chat infrastructure
#
# Responsibilities:
# - Feed voice transcripts into Scout's existing chat system
# - Use ScoutGenericToolsServiceV2 for agent processing
# - Stream responses back via Action Cable for TTS
# - Maintain conversation history in Scout's Redis store
#
# Usage:
#   service = VoiceAgentService.new(voice_session, transcript)
#   service.process
class VoiceAgentService
  attr_reader :voice_session, :transcript, :user, :entity

  def initialize(voice_session, transcript)
    @voice_session = voice_session
    @transcript = transcript
    @user = voice_session.user
    @entity = voice_session.entity
  end

  # Process the transcript through Scout's chat system
  def process
    Rails.logger.info({
      event: "voice_to_scout",
      session_id: voice_session.session_id,
      scout_session_id: scout_session_id,
      transcript: transcript
    }.to_json)

    # Broadcast "thinking" status
    broadcast_status("thinking")

    # Save user message to Scout's conversation history
    save_scout_message("user", transcript)

    # Process through Scout's generic tools service
    # Use faster/cheaper Haiku model for voice (ENV['BEDROCK_VOICE_MODEL'] or 'claude-3-haiku')
    main_chat_loadout = AgentLoadout.new(agent_role: "main_chat")
    scout_service = ScoutGenericToolsServiceV2.new(
      user,
      entity,
      scout_session_id,
      agent_loadout: main_chat_loadout,
      model: ENV.fetch('BEDROCK_VOICE_MODEL', 'claude-3-haiku')
    )

    # Get conversation history from Scout
    conversation_history = load_scout_history(20)

    # Process with streaming to capture response
    response_text = ""
    current_canvas = nil

    scout_service.process_message_with_tools_streaming(
      transcript,
      ->(update) {
        handle_scout_update(update, response_text)
      },
      conversation_history,
      nil # current_canvas
    )

    # Response was handled in the streaming callback
    broadcast_status("idle")

    { success: true, response: response_text }
  rescue => e
    Rails.logger.error({
      event: "voice_agent_error",
      session_id: voice_session.session_id,
      error: e.message,
      backtrace: e.backtrace.first(5)
    }.to_json)

    broadcast_error("I encountered an error processing your request. Please try again.")
    broadcast_status("error")

    { success: false, error: e.message }
  end

  private

  def scout_session_id
    # Link voice session to Scout session
    @scout_session_id ||= begin
      session_id = voice_session.metadata["scout_session_id"]

      unless session_id
        session_id = SecureRandom.uuid
        voice_session.metadata["scout_session_id"] = session_id
        voice_session.save!
      end

      session_id
    end
  end

  def handle_scout_update(update, response_text)
    case update
    when Hash
      if update[:type] == "content"
        # Accumulate response text
        content = update[:content] || update[:text] || ""
        response_text << content

        # Stream partial response for TTS
        broadcast_partial_response(content)
      elsif update[:final_response]
        # Final response received
        final_text = update[:content] || update[:message] || update[:response] || ""
        response_text.replace(final_text) if final_text.present?

        # Save assistant message to Scout history
        save_scout_message("assistant", final_text)

        # Add to voice session transcript
        voice_session.add_transcript(
          role: "assistant",
          content: final_text,
          timestamp: Time.current
        )

        # Broadcast complete response for TTS
        broadcast_response(final_text)
      elsif update[:canvas_data]
        # Canvas update - send to client
        broadcast_canvas(update[:canvas_data])
      end
    when String
      # Simple string response
      response_text << update
      broadcast_partial_response(update)
    end
  end

  def save_scout_message(role, content)
    # Use Scout's Redis storage pattern
    redis_key = "scout_messages:#{scout_session_id}"
    message = {
      role: role,
      content: content,
      timestamp: Time.current.iso8601
    }.to_json

    $redis.rpush(redis_key, message)
    $redis.expire(redis_key, 7.days.to_i)
  end

  def load_scout_history(limit = 20)
    redis_key = "scout_messages:#{scout_session_id}"
    messages_json = $redis.lrange(redis_key, -limit, -1)

    messages_json.map { |json| JSON.parse(json, symbolize_names: true) }
  rescue => e
    Rails.logger.error "Failed to load Scout history: #{e.message}"
    []
  end

  def broadcast_response(text)
    VoiceChannel.broadcast_to(voice_session, {
      type: "response",
      role: "assistant",
      content: text,
      timestamp: Time.current.iso8601,
      should_synthesize: true # Client should use Polly to speak this
    })
  end

  def broadcast_partial_response(text)
    VoiceChannel.broadcast_to(voice_session, {
      type: "partial_response",
      role: "assistant",
      content: text,
      timestamp: Time.current.iso8601,
      should_synthesize: false # Don't synthesize partial chunks
    })
  end

  def broadcast_canvas(canvas_data)
    VoiceChannel.broadcast_to(voice_session, {
      type: "canvas",
      data: canvas_data,
      timestamp: Time.current.iso8601
    })
  end

  def broadcast_status(status)
    VoiceChannel.broadcast_to(voice_session, {
      type: "status",
      status: status,
      timestamp: Time.current.iso8601
    })
  end

  def broadcast_error(message)
    VoiceChannel.broadcast_to(voice_session, {
      type: "error",
      message: message,
      timestamp: Time.current.iso8601
    })
  end
end
