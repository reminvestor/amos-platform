# VoiceAgentJob processes voice transcripts asynchronously
#
# This job is enqueued when a final transcript is received from Deepgram
# It processes the transcript through the agent workflow engine and
# broadcasts the response via Action Cable
class VoiceAgentJob < ApplicationJob
  queue_as :default

  def perform(voice_session_id, transcript)
    voice_session = VoiceSession.find(voice_session_id)

    service = VoiceAgentService.new(voice_session, transcript)
    service.process
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "VoiceAgentJob: Session not found - #{voice_session_id}"
  rescue => e
    Rails.logger.error({
      event: "voice_agent_job_error",
      voice_session_id: voice_session_id,
      error: e.message,
      backtrace: e.backtrace.first(10)
    }.to_json)

    # Broadcast error to client
    if voice_session
      VoiceChannel.broadcast_to(voice_session, {
        type: "error",
        message: "Failed to process your request. Please try again.",
        timestamp: Time.current.iso8601
      })
    end
  end
end
