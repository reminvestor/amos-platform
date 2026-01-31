# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class ToolConfirmationsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @user.update!(api_key: SecureRandom.hex(32)) unless @user.api_key.present?
        
        # Use the user's actual entity (what current_entity returns)
        @entity = @user.entity
        @entity ||= entities(:default)
        @user.update!(entity: @entity) unless @user.entity
        
        # Clear cache to ensure fresh user lookup
        Rails.cache.clear
        
        @pending = PendingToolConfirmation.create!(
          entity: @entity,
          user: @user,
          tool_name: "create_object",
          tool_args: { object_type: "contact", name: "Test" },
          action_description: "Create new contact",
          reason: "Write operation requires confirmation",
          session_id: "test-session-123",
          expires_at: 10.minutes.from_now
        )
      end

      teardown do
        PendingToolConfirmation.where(entity: @entity).destroy_all
      end

      def api_auth_headers
        {
          'Authorization' => "Bearer #{@user.api_key}",
          'Content-Type' => 'application/json',
          'Accept' => 'application/json'
        }
      end

      test "index returns list of pending confirmations" do
        get api_v1_tool_confirmations_url, headers: api_auth_headers

        assert_response :success
        json = JSON.parse(response.body)
        assert json["confirmations"].is_a?(Array)
        assert json["confirmations"].any? { |c| c["confirmation_id"] == @pending.confirmation_id }
      end

      test "index filters by session_id" do
        other = PendingToolConfirmation.create!(
          entity: @entity,
          user: @user,
          tool_name: "update_object",
          session_id: "other-session"
        )

        get api_v1_tool_confirmations_url(session_id: "test-session-123"), headers: api_auth_headers

        assert_response :success
        json = JSON.parse(response.body)
        
        confirmation_ids = json["confirmations"].map { |c| c["confirmation_id"] }
        assert_includes confirmation_ids, @pending.confirmation_id
        assert_not_includes confirmation_ids, other.confirmation_id
      end

      test "show returns confirmation details" do
        get api_v1_tool_confirmation_url(@pending.confirmation_id), headers: api_auth_headers

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal @pending.confirmation_id, json["confirmation_id"]
        assert_equal "create_object", json["tool_name"]
        assert_equal "pending", json["status"]
      end

      test "show returns 404 for unknown confirmation" do
        get api_v1_tool_confirmation_url("nonexistent-id"), headers: api_auth_headers

        assert_response :not_found
      end

      test "confirm changes status to confirmed" do
        post confirm_api_v1_tool_confirmations_url,
             params: { confirmation_id: @pending.confirmation_id }.to_json,
             headers: api_auth_headers

        assert_response :success
        json = JSON.parse(response.body)
        assert json["success"]

        @pending.reload
        assert_equal "confirmed", @pending.status
      end

      test "confirm returns error for expired confirmation" do
        @pending.update!(expires_at: 1.minute.ago)

        post confirm_api_v1_tool_confirmations_url,
             params: { confirmation_id: @pending.confirmation_id }.to_json,
             headers: api_auth_headers

        assert_response :gone
        json = JSON.parse(response.body)
        assert_not json["success"]
        assert_equal "Confirmation expired", json["error"]
      end

      test "confirm returns error for already resolved confirmation" do
        @pending.confirm!

        post confirm_api_v1_tool_confirmations_url,
             params: { confirmation_id: @pending.confirmation_id }.to_json,
             headers: api_auth_headers

        assert_response :unprocessable_entity
        json = JSON.parse(response.body)
        assert_not json["success"]
        assert json["error"].include?("already confirmed")
      end

      test "deny changes status to denied" do
        post deny_api_v1_tool_confirmations_url,
             params: { confirmation_id: @pending.confirmation_id }.to_json,
             headers: api_auth_headers

        assert_response :success
        json = JSON.parse(response.body)
        assert json["success"]

        @pending.reload
        assert_equal "denied", @pending.status
      end

      test "deny returns error for expired confirmation" do
        @pending.update!(expires_at: 1.minute.ago)

        post deny_api_v1_tool_confirmations_url,
             params: { confirmation_id: @pending.confirmation_id }.to_json,
             headers: api_auth_headers

        assert_response :gone
      end

      test "expire_all expires all pending confirmations" do
        expired = PendingToolConfirmation.create!(
          entity: @entity,
          user: @user,
          tool_name: "update_object",
          expires_at: 1.minute.ago,
          status: "pending"
        )

        delete expire_all_api_v1_tool_confirmations_url, headers: api_auth_headers

        assert_response :success
        json = JSON.parse(response.body)
        assert json["success"]
        assert json["expired_count"] >= 1

        expired.reload
        assert_equal "expired", expired.status
      end
    end
  end
end
