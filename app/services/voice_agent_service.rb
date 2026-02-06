# VoiceAgentService processes voice transcripts through V3 Agent Loop
#
# Responsibilities:
# - Feed voice transcripts into V3 agent loop
# - Stream responses back via Action Cable for TTS
# - Maintain conversation history
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

  # Process the transcript through V3 agent loop
  def process
    Rails.logger.info({
      event: "voice_to_v3",
      session_id: voice_session.session_id,
      scout_session_id: scout_session_id,
      transcript: transcript
    }.to_json)

    # Broadcast "thinking" status
    broadcast_status("thinking")

    # Save user message
    save_scout_message("user", transcript)

    # Use V3 agent loop — fast model for voice
    model = ENV.fetch("BEDROCK_VOICE_MODEL", "anthropic.claude-sonnet-4-v1")
    agent = V3::AgentLoop.new(
      user: user,
      entity: entity,
      session_id: scout_session_id,
      model: model
    )

    # Get conversation history
    conversation_history = load_scout_history(20)

    # Process with streaming to capture response
    response_text = ""

    result = agent.process_message_streaming(
      transcript,
      ->(chunk) { handle_v3_chunk(chunk, response_text) },
      conversation_history,
      nil # no canvas context for voice
    )

    # Save final response
    final_text = result.dig(:final_response, :message) || response_text
    if final_text.present? && response_text.blank?
      save_scout_message("assistant", final_text)
      voice_session.add_transcript(role: "assistant", content: final_text, timestamp: Time.current)
      broadcast_response(final_text)
    end

    broadcast_status("idle")

    { success: true, response: final_text }
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

  def handle_v3_chunk(chunk, response_text)
    return unless chunk.is_a?(Hash)

    case chunk[:type]
    when :content
      if chunk[:text].present?
        response_text << chunk[:text]
        broadcast_partial_response(chunk[:text])
      end
    when :canvas_suggestion
      broadcast_canvas({ canvas: chunk[:canvas], data: chunk[:data] })
    when :status
      # Status updates — don't accumulate
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
