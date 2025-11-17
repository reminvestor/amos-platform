module Api
  module Voice
    # VoiceSessionsController handles voice assistant session management
    #
    # Endpoints:
    # - POST /api/voice/sessions - Create new voice session
    # - GET /api/voice/sessions/:id - Get session details
    # - GET /api/voice/sessions/:id/deepgram_key - Get ephemeral Deepgram API key
    # - GET /api/voice/sessions/:id/polly_credentials - Get temporary AWS credentials for Polly
    # - PATCH /api/voice/sessions/:id/pause - Pause session
    # - PATCH /api/voice/sessions/:id/resume - Resume session
    # - PATCH /api/voice/sessions/:id/end - End session
    class VoiceSessionsController < ApplicationController
      before_action :authenticate_user!
      before_action :set_voice_session, only: [ :show, :deepgram_key, :eleven_labs_credentials, :polly_credentials, :pause, :resume, :end, :log_error ]
      before_action :authorize_session_access, only: [ :show, :deepgram_key, :eleven_labs_credentials, :polly_credentials, :pause, :resume, :end, :log_error ]

      # POST /api/voice/sessions
      def create
        @voice_session = VoiceSession.create!(
          user: current_user,
          entity: current_entity,
          metadata: session_metadata
        )

        render json: {
          session_id: @voice_session.session_id,
          status: @voice_session.status,
          started_at: @voice_session.started_at,
          websocket_channel: "VoiceChannel:#{@voice_session.session_id}"
        }, status: :created
      rescue => e
        Rails.logger.error "Failed to create voice session: #{e.message}"
        render json: { error: "Failed to create voice session" }, status: :unprocessable_entity
      end

      # GET /api/voice/sessions/:id
      def show
        render json: {
          session_id: @voice_session.session_id,
          status: @voice_session.status,
          started_at: @voice_session.started_at,
          ended_at: @voice_session.ended_at,
          duration: @voice_session.duration,
          transcript_history: @voice_session.transcript_history,
          keywords: @voice_session.keywords
        }
      end

      # GET /api/voice/sessions/:id/deepgram_key
      def deepgram_key
        service = DeepgramService.new(@voice_session)

        # Using main API key for demo (API key lacks permissions for temp key generation)
        # In production with proper Deepgram plan, use: service.generate_ephemeral_key
        render json: {
          api_key: service.send(:deepgram_api_key),
          websocket_url: service.send(:deepgram_websocket_url),
          config: service.websocket_config
        }
      rescue => e
        Rails.logger.error "Failed to get Deepgram credentials: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: { error: "Failed to get Deepgram credentials: #{e.message}" }, status: :internal_server_error
      end

      # GET /api/voice/sessions/:id/eleven_labs_credentials
      def eleven_labs_credentials
        service = ElevenLabsTranscriptionService.new(@voice_session)

        render json: service.connection_params
      rescue => e
        Rails.logger.error "Failed to get Eleven Labs credentials: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: { error: "Failed to get Eleven Labs credentials: #{e.message}" }, status: :internal_server_error
      end

      # GET /api/voice/sessions/:id/polly_credentials
      def polly_credentials
        service = PollyCredentialsService.new(@voice_session)
        credentials = service.generate_credentials

        render json: credentials
      rescue => e
        Rails.logger.error "Failed to generate Polly credentials: #{e.message}"
        render json: { error: "Failed to generate credentials" }, status: :internal_server_error
      end

      # PATCH /api/voice/sessions/:id/pause
      def pause
        @voice_session.pause!
        render json: { status: @voice_session.status }
      end

      # PATCH /api/voice/sessions/:id/resume
      def resume
        @voice_session.resume!
        render json: { status: @voice_session.status }
      end

      # PATCH /api/voice/sessions/:id/end
      def end
        @voice_session.end_session!
        render json: {
          status: @voice_session.status,
          ended_at: @voice_session.ended_at,
          duration: @voice_session.duration
        }
      end

      # POST /api/voice/sessions/:id/log_error
      # Log voice assistant errors for monitoring without exposing details to user
      def log_error
        error_type = params[:error_type]
        error_message = params[:error_message]
        provider = params[:provider] || "unknown"

        # Log to VoiceSession metadata
        @voice_session.log_error(
          error_type: error_type,
          error_message: error_message,
          provider: provider
        )

        # Log to Rails logger for monitoring
        Rails.logger.error("[Voice Error] Session: #{@voice_session.session_id}, Provider: #{provider}, Type: #{error_type}, Message: #{error_message}")

        # Log to ObservabilityEvent for admin dashboard visibility
        ObservabilityEvent.create!(
          event_type: "voice_error",
          entity: @voice_session.entity,
          user: @voice_session.user,
          metadata: {
            session_id: @voice_session.session_id,
            error_type: error_type,
            error_message: error_message,
            provider: provider,
            status: "error"
          }
        )

        # Log to VoiceMetricsService for analytics
        metrics_service = VoiceMetricsService.new
        metrics_service.record_session_metric(
          @voice_session,
          provider,
          success: false,
          error: "#{error_type}: #{error_message}",
          timestamp: Time.current
        )

        # Send Slack alert (async, non-blocking)
        send_slack_alert_async(error_type, error_message, provider)

        # Return generic success - no error details exposed
        render json: { status: "logged" }, status: :ok
      rescue => e
        Rails.logger.error "Failed to log voice error: #{e.message}"
        # Fail silently - don't disrupt user experience
        render json: { status: "ok" }, status: :ok
      end

      private

      def set_voice_session
        @voice_session = VoiceSession.find_by(session_id: params[:id])
        render json: { error: "Session not found" }, status: :not_found unless @voice_session
      end

      def authorize_session_access
        unless @voice_session&.entity_id == current_entity.id
          render json: { error: "Unauthorized" }, status: :forbidden
        end
      end

      def session_metadata
        {
          user_agent: request.user_agent,
          ip_address: request.remote_ip,
          created_from: "web"
        }
      end

      def send_slack_alert_async(error_type, error_message, provider)
        # Send Slack notification asynchronously via background job
        # This won't block the response to the user
        VoiceErrorSlackNotificationJob.perform_later(
          session_id: @voice_session.session_id,
          entity_name: @voice_session.entity.name,
          user_email: @voice_session.user.email,
          error_type: error_type,
          error_message: error_message,
          provider: provider
        )
      rescue => e
        # Log but don't fail if Slack notification fails
        Rails.logger.warn("Failed to queue Slack notification: #{e.message}")
      end
    end
  end
end
