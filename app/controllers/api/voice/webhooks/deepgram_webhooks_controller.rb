module Api
  module Voice
    module Webhooks
      # DeepgramWebhooksController receives transcript webhooks from Deepgram
      #
      # Endpoint:
      # - POST /api/voice/webhooks/deepgram - Receive final transcripts
      class DeepgramWebhooksController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :authenticate_user!
    before_action :verify_webhook_signature

    # POST /api/voice/webhooks/deepgram
    def create
      payload = JSON.parse(request.body.read)
      transcript_data = DeepgramService.parse_webhook(payload)

      # Extract session_id from metadata
      session_id = payload.dig("metadata", "extra", "session_id")

      unless session_id
        Rails.logger.warn "Deepgram webhook missing session_id"
        return head :bad_request
      end

      voice_session = VoiceSession.find_by(session_id: session_id)

      unless voice_session
        Rails.logger.warn "Deepgram webhook for unknown session: #{session_id}"
        return head :not_found
      end

      # Only process final transcripts
      if transcript_data[:is_final] && transcript_data[:transcript].present?
        process_transcript(voice_session, transcript_data)
      end

      head :ok
    rescue JSON::ParserError => e
      Rails.logger.error "Invalid JSON in Deepgram webhook: #{e.message}"
      head :bad_request
    rescue => e
      Rails.logger.error "Deepgram webhook error: #{e.message}"
      head :internal_server_error
    end

    private

    def verify_webhook_signature
      signature = request.headers["X-Deepgram-Signature"]
      payload = request.body.read
      request.body.rewind

      unless DeepgramService.validate_webhook_signature(payload, signature)
        Rails.logger.warn "Invalid Deepgram webhook signature"
        head :unauthorized
      end
    end

    def process_transcript(voice_session, transcript_data)
      # Add transcript to session history
      voice_session.add_transcript(
        role: "user",
        content: transcript_data[:transcript],
        timestamp: Time.current
      )

      # Broadcast to Action Cable
      ActionCable.server.broadcast(
        "voice_channel:#{voice_session.session_id}",
        {
          type: "transcript",
          role: "user",
          content: transcript_data[:transcript],
          confidence: transcript_data[:confidence],
          is_final: true,
          timestamp: Time.current.iso8601
        }
      )

      # Process through voice agent (async)
      VoiceAgentJob.perform_later(
        voice_session.id,
        transcript_data[:transcript]
      )

      Rails.logger.info({
        event: "transcript_received",
        session_id: voice_session.session_id,
        transcript: transcript_data[:transcript],
        confidence: transcript_data[:confidence]
      }.to_json)
    end
      end
    end
  end
end
