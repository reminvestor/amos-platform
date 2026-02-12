# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class WorkItemsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @entity = entities(:one)
        @user.update!(entity: @entity, api_key: SecureRandom.hex(32))

        # Create test work items
        @work_item = AgentWorkItem.create!(
          user: @user,
          entity: @entity,
          work_type: "task_completed",
          title: "Test Work Item",
          summary: "A test work item summary",
          priority: "normal",
          read: false,
          starred: false,
          archived: false,
          requires_action: false
        )

        @starred_item = AgentWorkItem.create!(
          user: @user,
          entity: @entity,
          work_type: "report_generated",
          title: "Starred Item",
          summary: "A starred work item",
          priority: "high",
          read: true,
          starred: true,
          archived: false,
          requires_action: false
        )

        @archived_item = AgentWorkItem.create!(
          user: @user,
          entity: @entity,
          work_type: "email_sent",
          title: "Archived Item",
          summary: "An archived work item",
          priority: "normal",
          read: true,
          starred: false,
          archived: true,
          requires_action: false
        )
      end

      teardown do
        AgentWorkItem.where(user: @user).destroy_all
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

      test "should get work items list with valid token" do
        get api_v1_work_items_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("data")
        assert response_body.key?("pagination")
        assert response_body.key?("counts")
      end

      test "work items list returns expected fields" do
        get api_v1_work_items_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        items = response_body["data"]

        assert items.any?

        item = items.find { |i| i["id"] == @work_item.id }
        assert_not_nil item
        assert_equal @work_item.title, item["title"]
        assert_equal @work_item.summary, item["summary"]
        assert_equal @work_item.work_type, item["work_type"]
        assert item.key?("read")
        assert item.key?("starred")
        assert item.key?("archived")
        assert item.key?("created_at")
      end

      test "work items list excludes archived by default" do
        get api_v1_work_items_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        item_ids = response_body["data"].map { |i| i["id"] }

        assert_includes item_ids, @work_item.id
        assert_not_includes item_ids, @archived_item.id
      end

      test "work items list filters by unread" do
        get api_v1_work_items_path,
          params: { filter: "unread" },
          headers: auth_headers,
          as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        item_ids = response_body["data"].map { |i| i["id"] }

        assert_includes item_ids, @work_item.id
        assert_not_includes item_ids, @starred_item.id
      end

      test "work items list filters by starred" do
        get api_v1_work_items_path,
          params: { filter: "starred" },
          headers: auth_headers,
          as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        item_ids = response_body["data"].map { |i| i["id"] }

        assert_includes item_ids, @starred_item.id
      end

      test "work items list filters by archived" do
        get api_v1_work_items_path,
          params: { filter: "archived" },
          headers: auth_headers,
          as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        item_ids = response_body["data"].map { |i| i["id"] }

        assert_includes item_ids, @archived_item.id
        assert_not_includes item_ids, @work_item.id
      end

      test "work items list returns counts" do
        get api_v1_work_items_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        counts = response_body["counts"]

        assert counts.key?("unread")
        assert counts.key?("starred")
        assert counts.key?("total")
        assert counts["starred"] >= 1, "Expected at least 1 starred item"
      end

      test "work items list requires authentication" do
        get api_v1_work_items_path, as: :json

        assert_response :unauthorized
      end

      test "work items list rejects invalid token" do
        get api_v1_work_items_path,
          headers: { "Authorization" => "Bearer invalid_token" },
          as: :json

        assert_response :unauthorized
      end

      test "work items list only returns user's own items" do
        other_user = User.create!(
          email: "other_work_#{SecureRandom.hex(4)}@test.com",
          password: "Password123!",
          entity: @entity,
          api_key: SecureRandom.hex(32)
        )

        other_item = AgentWorkItem.create!(
          user: other_user,
          entity: @entity,
          work_type: "task_completed",
          title: "Other User's Item",
          priority: "normal"
        )

        get api_v1_work_items_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        item_ids = response_body["data"].map { |i| i["id"] }

        assert_not_includes item_ids, other_item.id

        other_item.destroy
        other_user.destroy
      end

      # ====================================================================
      # SHOW Tests
      # ====================================================================

      test "should get work item details" do
        get api_v1_work_item_path(@work_item), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal @work_item.id, response_body["id"]
        assert_equal @work_item.title, response_body["title"]
      end

      test "should return 404 for non-existent work item" do
        get api_v1_work_item_path(id: 999999), headers: auth_headers, as: :json

        assert_response :not_found
      end

      test "should return 404 for other user's work item" do
        other_user = User.create!(
          email: "other_show_#{SecureRandom.hex(4)}@test.com",
          password: "Password123!",
          entity: @entity,
          api_key: SecureRandom.hex(32)
        )

        get api_v1_work_item_path(@work_item),
          headers: { "Authorization" => "Bearer #{other_user.api_key}" },
          as: :json

        assert_response :not_found

        other_user.destroy
      end

      # ====================================================================
      # MARK_READ Tests
      # ====================================================================

      test "should mark work item as read" do
        assert_equal false, @work_item.read

        post mark_read_api_v1_work_item_path(@work_item),
          headers: auth_headers,
          as: :json

        assert_response :success

        @work_item.reload
        assert_equal true, @work_item.read
      end

      # ====================================================================
      # TOGGLE_STARRED Tests
      # ====================================================================

      test "should toggle starred status" do
        assert_equal false, @work_item.starred

        post toggle_starred_api_v1_work_item_path(@work_item),
          headers: auth_headers,
          as: :json

        assert_response :success

        @work_item.reload
        assert_equal true, @work_item.starred

        # Toggle again
        post toggle_starred_api_v1_work_item_path(@work_item),
          headers: auth_headers,
          as: :json

        assert_response :success

        @work_item.reload
        assert_equal false, @work_item.starred
      end

      # ====================================================================
      # ARCHIVE Tests
      # ====================================================================

      test "should archive work item" do
        assert_equal false, @work_item.archived

        post archive_api_v1_work_item_path(@work_item),
          headers: auth_headers,
          as: :json

        assert_response :success

        @work_item.reload
        assert_equal true, @work_item.archived
      end

      test "should unarchive work item" do
        assert_equal true, @archived_item.archived

        post unarchive_api_v1_work_item_path(@archived_item),
          headers: auth_headers,
          as: :json

        assert_response :success

        @archived_item.reload
        assert_equal false, @archived_item.archived
      end

      # ====================================================================
      # MARK_ALL_READ Tests
      # ====================================================================

      test "should mark all items as read" do
        # Create another unread item
        unread_item = AgentWorkItem.create!(
          user: @user,
          entity: @entity,
          work_type: "task_completed",
          title: "Another Unread Item",
          priority: "normal",
          read: false,
          archived: false
        )

        post mark_all_read_api_v1_work_items_path,
          headers: auth_headers,
          as: :json

        assert_response :success

        @work_item.reload
        unread_item.reload

        assert_equal true, @work_item.read
        assert_equal true, unread_item.read

        unread_item.destroy
      end
    end
  end
end
