# VoiceChannel handles real-time voice assistant communication via WebSocket
#
# Streams:
# - transcript updates (user and assistant)
# - agent status updates (thinking, processing, etc.)
# - errors and notifications
#
# Usage (JavaScript):
#   const channel = consumer.subscriptions.create(
#     { channel: "VoiceChannel", session_id: "uuid" },
#     {
#       received(data) {
#         // Handle incoming messages
#       }
#     }
#   );
class VoiceChannel < ApplicationCable::Channel
  def subscribed
    session_id = params[:session_id]

    unless session_id
      reject
      return
    end

    voice_session = VoiceSession.find_by(session_id: session_id)

    unless voice_session
      reject
      return
    end

    # Verify user has access to this session
    unless voice_session.entity_id == current_user&.entity_id
      reject
      return
    end

    stream_for voice_session

    Rails.logger.info({
      event: "voice_channel_subscribed",
      session_id: session_id,
      user_id: current_user&.id
    }.to_json)

    # Send initial session state
    transmit({
      type: "session_started",
      session_id: voice_session.session_id,
      status: voice_session.status,
      keywords: voice_session.keywords,
      transcript_history: voice_session.transcript_history
    })
  end

  def unsubscribed
    Rails.logger.info({
      event: "voice_channel_unsubscribed",
      user_id: current_user&.id
    }.to_json)
  end

  def receive(data)
    # Handle client messages (e.g., interim transcripts, status updates)
    case data["type"]
    when "interim_transcript"
      handle_interim_transcript(data)
    when "pause"
      handle_pause
    when "resume"
      handle_resume
    end
  end

  private

  def handle_interim_transcript(data)
    # Broadcast interim transcript to other listeners (e.g., admin monitoring)
    voice_session = VoiceSession.find_by(session_id: params[:session_id])
    return unless voice_session

    VoiceChannel.broadcast_to(voice_session, {
      type: "interim_transcript",
      role: "user",
      content: data["content"],
      is_final: false,
      timestamp: Time.current.iso8601
    })
  end

  def handle_pause
    voice_session = VoiceSession.find_by(session_id: params[:session_id])
    return unless voice_session

    voice_session.pause!

    VoiceChannel.broadcast_to(voice_session, {
      type: "status_change",
      status: "paused",
      timestamp: Time.current.iso8601
    })
  end

  def handle_resume
    voice_session = VoiceSession.find_by(session_id: params[:session_id])
    return unless voice_session

    voice_session.resume!

    VoiceChannel.broadcast_to(voice_session, {
      type: "status_change",
      status: "active",
      timestamp: Time.current.iso8601
    })
  end
end
