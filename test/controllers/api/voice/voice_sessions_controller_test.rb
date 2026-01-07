require "test_helper"

module Api
  module Voice
    class VoiceSessionsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @entity = entities(:one)
        @user.update!(entity: @entity)

        sign_in @user

        @voice_session = VoiceSession.create!(
          user: @user,
          entity: @entity,
          session_id: SecureRandom.uuid,
          status: "active"
        )
      end

      # ====================================================================
      # CREATE SESSION Tests
      # ====================================================================

      test "should create voice session" do
        assert_difference("VoiceSession.count") do
          post api_voice_sessions_path, as: :json
        end

        assert_response :created

        response_body = JSON.parse(response.body)
        assert response_body.key?("session_id")
        assert response_body.key?("status")
        assert response_body.key?("started_at")
        assert_equal "active", response_body["status"]
      end

      test "session creation sets correct attributes" do
        post api_voice_sessions_path, as: :json

        assert_response :created

        session = VoiceSession.last
        assert_equal @user, session.user
        assert_equal @entity, session.entity
        assert_equal "active", session.status
      end

      # ====================================================================
      # GET SESSION Tests
      # ====================================================================

      test "should get voice session details" do
        get api_voice_session_path(@voice_session.session_id), as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal @voice_session.session_id, response_body["session_id"]
        assert_equal "active", response_body["status"]
        assert response_body.key?("started_at")
      end

      test "should not get session from different entity" do
        other_user = users(:two)
        other_entity = Entity.create!(name: "Other Entity", subdomain: "other-entity-#{SecureRandom.hex(4)}")
        other_user.update!(entity: other_entity)
        sign_in other_user

        get api_voice_session_path(@voice_session.session_id), as: :json

        assert_response :forbidden
      end

      test "returns 404 for non-existent session" do
        get api_voice_session_path("non-existent-id"), as: :json

        assert_response :not_found
      end

      # ====================================================================
      # ELEVEN LABS CREDENTIALS Tests
      # ====================================================================

      test "should get Eleven Labs credentials" do
        with_env("ELEVEN_LABS_API_KEY" => "test_api_key_12345") do
          get eleven_labs_credentials_api_voice_session_path(@voice_session.session_id), as: :json

          assert_response :success

          response_body = JSON.parse(response.body)
          assert response_body.key?("websocket_url")
          assert response_body.key?("api_key")
          assert response_body.key?("config")

          assert_equal "test_api_key_12345", response_body["api_key"]
          assert response_body["websocket_url"].start_with?("wss://")
        end
      end

      test "Eleven Labs credentials include full configuration" do
        with_env("ELEVEN_LABS_API_KEY" => "test_key") do
          get eleven_labs_credentials_api_voice_session_path(@voice_session.session_id), as: :json

          assert_response :success

          response_body = JSON.parse(response.body)
          config = response_body["config"]

          assert_equal "pcm_16000", config["encoding"]
          assert_equal 16000, config["sample_rate"]
          assert_equal 1, config["channels"]
          assert_equal "scribe-v3-realtime", config["model"]
          assert_equal "en", config["language"]
          assert config["punctuate"]
          assert config["include_partial_results"]
          assert config["latency_optimized"]
        end
      end

      test "Eleven Labs credentials endpoint requires authentication" do
        sign_out @user

        get eleven_labs_credentials_api_voice_session_path(@voice_session.session_id), as: :json

        assert_response :unauthorized
      end

      test "Eleven Labs credentials endpoint requires session authorization" do
        other_user = users(:two)
        other_entity = Entity.create!(name: "Other Entity", subdomain: "other-eleven-#{SecureRandom.hex(4)}")
        other_user.update!(entity: other_entity)
        sign_in other_user

        get eleven_labs_credentials_api_voice_session_path(@voice_session.session_id), as: :json

        assert_response :forbidden
      end

      test "Eleven Labs credentials returns 404 for non-existent session" do
        get eleven_labs_credentials_api_voice_session_path("non-existent"), as: :json

        assert_response :not_found
      end

      test "Eleven Labs credentials handles missing API key gracefully" do
        with_env("ELEVEN_LABS_API_KEY" => nil) do
          get eleven_labs_credentials_api_voice_session_path(@voice_session.session_id), as: :json

          assert_response :internal_server_error

          response_body = JSON.parse(response.body)
          assert response_body.key?("error")
          assert response_body["error"].include?("Failed to get Eleven Labs credentials")
        end
      end

      # ====================================================================
      # DEEPGRAM CREDENTIALS Tests (Backward Compatibility)
      # ====================================================================

      test "should still get Deepgram credentials (fallback provider)" do
        with_env("DEEPGRAM_API_KEY" => "test_deepgram_key") do
          get deepgram_key_api_voice_session_path(@voice_session.session_id), as: :json

          assert_response :success

          response_body = JSON.parse(response.body)
          assert response_body.key?("api_key")
          assert response_body.key?("websocket_url")
          assert response_body.key?("config")
        end
      end

      # ====================================================================
      # END SESSION Tests
      # ====================================================================

      test "should end voice session" do
        patch end_api_voice_session_path(@voice_session.session_id), as: :json

        assert_response :success

        @voice_session.reload
        assert_equal "ended", @voice_session.status
        assert_not_nil @voice_session.ended_at
      end

      test "should not end session from different entity" do
        other_user = users(:two)
        other_entity = Entity.create!(name: "Other Entity", subdomain: "other-end-#{SecureRandom.hex(4)}")
        other_user.update!(entity: other_entity)
        sign_in other_user

        patch end_api_voice_session_path(@voice_session.session_id), as: :json

        assert_response :forbidden
      end

      # ====================================================================
      # AUTHENTICATION Tests
      # ====================================================================

      test "all voice endpoints require authentication" do
        sign_out @user

        # Test create
        post api_voice_sessions_path, as: :json
        assert_response :unauthorized

        # Test show
        get api_voice_session_path(@voice_session.session_id), as: :json
        assert_response :unauthorized

        # Test Eleven Labs credentials
        get eleven_labs_credentials_api_voice_session_path(@voice_session.session_id), as: :json
        assert_response :unauthorized

        # Test deepgram key
        get deepgram_key_api_voice_session_path(@voice_session.session_id), as: :json
        assert_response :unauthorized

        # Test end
        patch end_api_voice_session_path(@voice_session.session_id), as: :json
        assert_response :unauthorized
      end

      # ====================================================================
      # ENTITY SCOPING Tests
      # ====================================================================

      test "sessions are properly scoped to entity" do
        other_user = users(:two)
        other_entity = Entity.create!(name: "Other Entity", subdomain: "other-scope-#{SecureRandom.hex(4)}")
        other_user.update!(entity: other_entity)

        other_session = VoiceSession.create!(
          user: other_user,
          entity: other_entity,
          session_id: SecureRandom.uuid,
          status: "active"
        )

        # Current user should not see other entity's session
        sign_in @user
        get api_voice_session_path(other_session.session_id), as: :json
        assert_response :forbidden

        # Other user should see their own session
        sign_in other_user
        get api_voice_session_path(other_session.session_id), as: :json
        assert_response :success
      end

      # ====================================================================
      # METADATA Tests
      # ====================================================================

      test "session creation includes request metadata" do
        post api_voice_sessions_path, as: :json

        session = VoiceSession.last
        metadata = session.metadata

        assert metadata.key?("user_agent")
        assert metadata.key?("ip_address")
        assert metadata.key?("created_from")
        assert_equal "web", metadata["created_from"]
      end

      # ====================================================================
      # ERROR HANDLING Tests
      # ====================================================================

      test "gracefully handles unexpected errors during session creation" do
        VoiceSession.expects(:create!).raises(StandardError.new("Database error"))

        post api_voice_sessions_path, as: :json

        assert_response :unprocessable_entity

        response_body = JSON.parse(response.body)
        assert response_body.key?("error")
      end

      test "Eleven Labs credentials endpoint handles service errors" do
        with_env("ELEVEN_LABS_API_KEY" => "test_key") do
          ElevenLabsTranscriptionService.any_instance.expects(:connection_params)
            .raises(StandardError.new("Service error"))

          get eleven_labs_credentials_api_voice_session_path(@voice_session.session_id), as: :json

          assert_response :internal_server_error

          response_body = JSON.parse(response.body)
          assert response_body.key?("error")
        end
      end

      private

      def with_env(vars)
        original_vars = {}
        vars.each do |key, value|
          original_vars[key] = ENV[key]
          if value.nil?
            ENV.delete(key)
          else
            ENV[key] = value
          end
        end

        yield

        original_vars.each do |key, value|
          if value.nil?
            ENV.delete(key)
          else
            ENV[key] = value
          end
        end
      end
    end
  end
end
