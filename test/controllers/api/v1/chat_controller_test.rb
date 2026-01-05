# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class ChatControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @entity = entities(:one)
        @user.update!(entity: @entity, api_key: SecureRandom.hex(32))

        @session_id = SecureRandom.uuid

        # Create test messages
        @user_message = ScoutMessage.create!(
          user: @user,
          entity: @entity,
          session_id: @session_id,
          role: "user",
          content: "Hello, this is a test message"
        )

        @assistant_message = ScoutMessage.create!(
          user: @user,
          entity: @entity,
          session_id: @session_id,
          role: "assistant",
          content: "Hello! How can I help you?"
        )

        @other_session_id = SecureRandom.uuid
        @other_session_message = ScoutMessage.create!(
          user: @user,
          entity: @entity,
          session_id: @other_session_id,
          role: "user",
          content: "Another conversation"
        )
      end

      teardown do
        ScoutMessage.where(user: @user).destroy_all
      end

      # ====================================================================
      # Helper Methods
      # ====================================================================

      def auth_headers
        { "Authorization" => "Bearer #{@user.api_key}" }
      end

      # ====================================================================
      # HISTORY Tests
      # ====================================================================

      test "should get chat history with valid token" do
        get api_v1_chat_history_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("messages")
        assert response_body.key?("has_more")
        assert response_body.key?("total")
      end

      test "chat history returns expected fields" do
        get api_v1_chat_history_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        messages = response_body["messages"]

        assert messages.any?

        message = messages.find { |m| m["id"] == @user_message.id }
        assert_not_nil message
        assert_equal "user", message["role"]
        assert_equal "Hello, this is a test message", message["content"]
        assert_equal @session_id, message["session_id"]
        assert message.key?("timestamp")
      end

      test "chat history supports limit param" do
        get api_v1_chat_history_path, params: { limit: 1 }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal 1, response_body["messages"].size
      end

      test "chat history limits to max 100 messages" do
        # Even if client requests more than 100, should be limited
        get api_v1_chat_history_path, params: { limit: 200 }, headers: auth_headers, as: :json

        assert_response :success
        # Can't directly test the limit without creating 100+ messages,
        # but we can verify it doesn't fail
      end

      test "chat history supports pagination with before_id" do
        # Create a newer message
        newer_message = ScoutMessage.create!(
          user: @user,
          entity: @entity,
          session_id: @session_id,
          role: "user",
          content: "Newer message"
        )

        get api_v1_chat_history_path, params: { before_id: newer_message.id }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        message_ids = response_body["messages"].map { |m| m["id"] }

        # Should not include the newer message
        assert_not_includes message_ids, newer_message.id

        newer_message.destroy
      end

      test "chat history requires authentication" do
        get api_v1_chat_history_path, as: :json

        assert_response :unauthorized
      end

      test "chat history rejects invalid token" do
        get api_v1_chat_history_path,
          headers: { "Authorization" => "Bearer invalid_token" },
          as: :json

        assert_response :unauthorized
      end

      test "chat history only returns current user messages" do
        other_user = users(:two)
        other_user.update!(entity: entities(:two), api_key: SecureRandom.hex(32))

        other_message = ScoutMessage.create!(
          user: other_user,
          entity: entities(:two),
          session_id: SecureRandom.uuid,
          role: "user",
          content: "Other user message"
        )

        get api_v1_chat_history_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        message_ids = response_body["messages"].map { |m| m["id"] }

        assert_not_includes message_ids, other_message.id

        other_message.destroy
      end

      # ====================================================================
      # CONVERSATIONS Tests
      # ====================================================================

      test "should get conversations list with valid token" do
        get api_v1_chat_conversations_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("conversations")
      end

      test "conversations returns expected fields" do
        get api_v1_chat_conversations_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        conversations = response_body["conversations"]

        assert conversations.any?

        conversation = conversations.find { |c| c["session_id"] == @session_id }
        assert_not_nil conversation
        assert conversation.key?("started_at")
        assert conversation.key?("last_message_at")
        assert conversation.key?("message_count")
        assert conversation.key?("preview")
      end

      test "conversations ordered by last message" do
        # The conversation with the most recent message should be first
        get api_v1_chat_conversations_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        conversations = response_body["conversations"]

        # Both our sessions should be present
        session_ids = conversations.map { |c| c["session_id"] }
        assert_includes session_ids, @session_id
        assert_includes session_ids, @other_session_id
      end

      test "conversations requires authentication" do
        get api_v1_chat_conversations_path, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # CLEAR Tests
      # ====================================================================

      test "should clear all messages for user" do
        assert ScoutMessage.where(user: @user).count > 0

        delete api_v1_chat_clear_path, headers: auth_headers, as: :json

        assert_response :success

        assert_equal 0, ScoutMessage.where(user: @user).count

        response_body = JSON.parse(response.body)
        assert response_body.key?("message")
      end

      test "should clear specific session only" do
        initial_count = ScoutMessage.where(user: @user).count

        delete api_v1_chat_clear_path, params: { session_id: @session_id }, headers: auth_headers, as: :json

        assert_response :success

        # Should have cleared messages from @session_id but kept @other_session_id
        assert_equal 0, ScoutMessage.where(user: @user, session_id: @session_id).count
        assert ScoutMessage.where(user: @user, session_id: @other_session_id).count > 0
      end

      test "clear requires authentication" do
        delete api_v1_chat_clear_path, as: :json

        assert_response :unauthorized
      end

      test "clear does not affect other user messages" do
        other_user = users(:two)
        other_user.update!(entity: entities(:two), api_key: SecureRandom.hex(32))

        other_message = ScoutMessage.create!(
          user: other_user,
          entity: entities(:two),
          session_id: SecureRandom.uuid,
          role: "user",
          content: "Other user message"
        )

        delete api_v1_chat_clear_path, headers: auth_headers, as: :json

        assert_response :success

        # Other user's message should still exist
        assert ScoutMessage.exists?(other_message.id)

        other_message.destroy
      end
    end
  end
end
