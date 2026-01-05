# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class NotificationsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @entity = entities(:one)
        @user.update!(entity: @entity, api_key: SecureRandom.hex(32))

        # Create test notifications
        @unread_notification = UserNotification.create!(
          entity: @entity,
          user: @user,
          notification_type: "task_completed",
          title: "Task Done",
          body: "Your task has been completed",
          channel: "in_app",
          priority: "normal",
          read: false
        )

        @read_notification = UserNotification.create!(
          entity: @entity,
          user: @user,
          notification_type: "agent_message",
          title: "Agent Update",
          body: "Agent has a message",
          channel: "in_app",
          priority: "normal",
          read: true,
          read_at: 1.hour.ago
        )

        @urgent_notification = UserNotification.create!(
          entity: @entity,
          user: @user,
          notification_type: "action_required",
          title: "Action Required",
          body: "Please take action",
          channel: "in_app",
          priority: "urgent",
          read: false
        )
      end

      teardown do
        UserNotification.where(user: @user).destroy_all
      end

      # ====================================================================
      # Helper Methods
      # ====================================================================

      def auth_headers
        { "Authorization" => "Bearer #{@user.api_key}" }
      end

      # ====================================================================
      # INDEX Tests
      # ====================================================================

      test "should get notifications list with valid token" do
        get api_v1_notifications_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("data")
        assert response_body.key?("pagination")
        assert response_body.key?("unread_count")
      end

      test "notifications list returns expected fields" do
        get api_v1_notifications_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        notifications = response_body["data"]

        assert notifications.any?

        notification = notifications.find { |n| n["id"] == @unread_notification.id }
        assert_not_nil notification
        assert_equal "task_completed", notification["notification_type"]
        assert_equal "Task Done", notification["title"]
        assert_equal "Your task has been completed", notification["body"]
        assert_equal "normal", notification["priority"]
        assert_equal false, notification["read"]
        assert notification.key?("icon")
        assert notification.key?("color_class")
        assert notification.key?("time_ago")
      end

      test "notifications list includes pagination info" do
        get api_v1_notifications_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        pagination = response_body["pagination"]

        assert pagination.key?("current_page")
        assert pagination.key?("total_pages")
        assert pagination.key?("total_count")
        assert pagination.key?("per_page")
      end

      test "notifications list can filter unread only" do
        get api_v1_notifications_path, params: { unread_only: "true" }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        notifications = response_body["data"]

        notification_ids = notifications.map { |n| n["id"] }
        assert_includes notification_ids, @unread_notification.id
        assert_includes notification_ids, @urgent_notification.id
        assert_not_includes notification_ids, @read_notification.id
      end

      test "notifications list requires authentication" do
        get api_v1_notifications_path, as: :json

        assert_response :unauthorized
      end

      test "notifications list rejects invalid token" do
        get api_v1_notifications_path,
          headers: { "Authorization" => "Bearer invalid_token" },
          as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # SHOW Tests
      # ====================================================================

      test "should get notification details with valid token" do
        get api_v1_notification_path(@unread_notification), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal @unread_notification.id, response_body["id"]
        assert_equal "Task Done", response_body["title"]
      end

      test "should return 404 for non-existent notification" do
        get api_v1_notification_path(id: 999999), headers: auth_headers, as: :json

        assert_response :not_found
      end

      test "notification show requires authentication" do
        get api_v1_notification_path(@unread_notification), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # UNREAD_COUNT Tests
      # ====================================================================

      test "should get unread count" do
        get unread_count_api_v1_notifications_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("unread_count")
        assert response_body.key?("urgent_count")
        assert_equal 2, response_body["unread_count"]  # unread + urgent
        assert_equal 1, response_body["urgent_count"]  # just urgent
      end

      test "unread count requires authentication" do
        get unread_count_api_v1_notifications_path, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # MARK_READ Tests
      # ====================================================================

      test "should mark notification as read" do
        assert_equal false, @unread_notification.read

        post mark_read_api_v1_notification_path(@unread_notification), headers: auth_headers, as: :json

        assert_response :success

        @unread_notification.reload
        assert_equal true, @unread_notification.read
        assert_not_nil @unread_notification.read_at
      end

      test "mark read returns updated notification" do
        post mark_read_api_v1_notification_path(@unread_notification), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["read"]
        assert_not_nil response_body["read_at"]
      end

      test "mark read requires authentication" do
        post mark_read_api_v1_notification_path(@unread_notification), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # MARK_ALL_READ Tests
      # ====================================================================

      test "should mark all notifications as read" do
        post mark_all_read_api_v1_notifications_path, headers: auth_headers, as: :json

        assert_response :success

        @unread_notification.reload
        @urgent_notification.reload

        assert_equal true, @unread_notification.read
        assert_equal true, @urgent_notification.read
      end

      test "mark all read returns success message" do
        post mark_all_read_api_v1_notifications_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("message")
      end

      test "mark all read requires authentication" do
        post mark_all_read_api_v1_notifications_path, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # DISMISS Tests
      # ====================================================================

      test "should dismiss notification" do
        assert_equal false, @unread_notification.dismissed

        post dismiss_api_v1_notification_path(@unread_notification), headers: auth_headers, as: :json

        assert_response :no_content

        @unread_notification.reload
        assert_equal true, @unread_notification.dismissed
        assert_not_nil @unread_notification.dismissed_at
      end

      test "dismiss requires authentication" do
        post dismiss_api_v1_notification_path(@unread_notification), as: :json

        assert_response :unauthorized
      end

      test "should return 404 when dismissing non-existent notification" do
        post dismiss_api_v1_notification_path(id: 999999), headers: auth_headers, as: :json

        assert_response :not_found
      end
    end
  end
end
