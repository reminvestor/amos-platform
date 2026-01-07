# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class ActivitiesControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @entity = entities(:one)
        @user.update!(entity: @entity, api_key: SecureRandom.hex(32))

        # Create test contact
        @contact = Contact.create!(
          entity: @entity,
          user: @user,
          email: "test_activity@example.com",
          first_name: "Activity",
          last_name: "Test"
        )

        # Create test activities
        @note_activity = Activity.create!(
          entity: @entity,
          contact: @contact,
          user: @user,
          activity_type: "note",
          subject: "Test Note",
          description: "A test note",
          status: "completed"
        )

        @task_activity = Activity.create!(
          entity: @entity,
          contact: @contact,
          user: @user,
          activity_type: "task",
          subject: "Test Task",
          description: "A test task",
          status: "pending",
          priority: "high",
          due_at: 1.day.from_now
        )

        @overdue_task = Activity.create!(
          entity: @entity,
          contact: @contact,
          user: @user,
          activity_type: "task",
          subject: "Overdue Task",
          description: "An overdue task",
          status: "pending",
          priority: "urgent",
          due_at: 1.day.ago
        )
      end

      teardown do
        Activity.where(entity: @entity).destroy_all
        Contact.where(entity: @entity, email: "test_activity@example.com").destroy_all
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

      test "should get activities list with valid token" do
        get api_v1_activities_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert response_body.key?("activities")
        assert response_body.key?("total_count")
        assert response_body.key?("stats")
      end

      test "activities list returns expected fields" do
        get api_v1_activities_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        activities = response_body["activities"]

        assert activities.any?

        activity = activities.find { |a| a["id"] == @note_activity.id }
        assert_not_nil activity
        assert_equal "note", activity["activity_type"]
        assert_equal "Test Note", activity["subject"]
        assert_equal "A test note", activity["description"]
        assert activity.key?("type_icon")
        assert activity.key?("type_color")
        assert activity.key?("contact")
      end

      test "activities list can filter by type" do
        get api_v1_activities_path, params: { type: "task" }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        activities = response_body["activities"]

        activity_ids = activities.map { |a| a["id"] }
        assert_includes activity_ids, @task_activity.id
        assert_not_includes activity_ids, @note_activity.id
      end

      test "activities list can filter by status" do
        get api_v1_activities_path, params: { status: "pending" }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        activities = response_body["activities"]

        activities.each do |a|
          assert_equal "pending", a["status"]
        end
      end

      test "activities list can filter by contact" do
        get api_v1_activities_path, params: { contact_id: @contact.id }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        activities = response_body["activities"]

        activities.each do |a|
          assert_equal @contact.id, a["contact"]["id"]
        end
      end

      test "activities list requires authentication" do
        get api_v1_activities_path, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # TASKS Tests
      # ====================================================================

      test "should get tasks grouped by status" do
        get tasks_api_v1_activities_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert response_body.key?("tasks")
        assert response_body.key?("counts")

        tasks = response_body["tasks"]
        assert tasks.key?("overdue")
        assert tasks.key?("due_today")
        assert tasks.key?("upcoming")
        assert tasks.key?("pending")
        assert tasks.key?("completed_recently")
      end

      test "tasks returns counts" do
        get tasks_api_v1_activities_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        counts = response_body["counts"]

        assert counts.key?("overdue")
        assert counts.key?("due_today")
        assert counts.key?("open")
        assert counts["overdue"] >= 1  # We have an overdue task
      end

      test "tasks requires authentication" do
        get tasks_api_v1_activities_path, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # TIMELINE Tests
      # ====================================================================

      test "should get timeline for contact" do
        get timeline_api_v1_activities_path, params: { contact_id: @contact.id }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert response_body.key?("timeline")
      end

      test "timeline returns expected fields" do
        get timeline_api_v1_activities_path, params: { contact_id: @contact.id }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        timeline = response_body["timeline"]

        assert timeline.any?

        entry = timeline.first
        assert entry.key?("id")
        assert entry.key?("type")
        assert entry.key?("icon")
        assert entry.key?("label")
        assert entry.key?("timestamp")
      end

      test "timeline requires authentication" do
        get timeline_api_v1_activities_path, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # SHOW Tests
      # ====================================================================

      test "should get activity details" do
        get api_v1_activity_path(@note_activity), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert_equal @note_activity.id, response_body["activity"]["id"]
        assert_equal "Test Note", response_body["activity"]["subject"]
      end

      test "show returns 404 for non-existent activity" do
        get api_v1_activity_path(id: 999999), headers: auth_headers, as: :json

        assert_response :not_found
      end

      test "show requires authentication" do
        get api_v1_activity_path(@note_activity), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # CREATE Tests
      # ====================================================================

      test "should create activity" do
        assert_difference("Activity.count", 1) do
          post api_v1_activities_path, params: {
            activity: {
              contact_id: @contact.id,
              activity_type: "note",
              subject: "New Note",
              description: "A new note created via API"
            }
          }, headers: auth_headers, as: :json
        end

        assert_response :created

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert_equal "New Note", response_body["activity"]["subject"]
      end

      test "create requires authentication" do
        post api_v1_activities_path, params: {
          activity: {
            contact_id: @contact.id,
            activity_type: "note",
            subject: "Test"
          }
        }, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # LOG_NOTE Tests
      # ====================================================================

      test "should log note for contact" do
        post log_note_api_v1_activities_path, params: {
          contact_id: @contact.id,
          description: "Quick note from API"
        }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert_equal "note", response_body["activity"]["activity_type"]
      end

      test "log note returns 404 for non-existent contact" do
        post log_note_api_v1_activities_path, params: {
          contact_id: 999999,
          description: "Test note"
        }, headers: auth_headers, as: :json

        assert_response :not_found
      end

      # ====================================================================
      # CREATE_TASK Tests
      # ====================================================================

      test "should create task" do
        post create_task_api_v1_activities_path, params: {
          contact_id: @contact.id,
          subject: "New Task from API",
          description: "Task description",
          priority: "high",
          due_at: 2.days.from_now.iso8601
        }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert_equal "task", response_body["activity"]["activity_type"]
        assert_equal "New Task from API", response_body["activity"]["subject"]
        assert_equal "high", response_body["activity"]["priority"]
      end

      # ====================================================================
      # UPDATE Tests
      # ====================================================================

      test "should update activity" do
        patch api_v1_activity_path(@task_activity), params: {
          activity: {
            subject: "Updated Task Subject",
            priority: "low"
          }
        }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert_equal "Updated Task Subject", response_body["activity"]["subject"]
        assert_equal "low", response_body["activity"]["priority"]
      end

      test "update requires authentication" do
        patch api_v1_activity_path(@task_activity), params: {
          activity: { subject: "Hacked" }
        }, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # DESTROY Tests
      # ====================================================================

      test "should delete activity" do
        assert_difference("Activity.count", -1) do
          delete api_v1_activity_path(@note_activity), headers: auth_headers, as: :json
        end

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
      end

      test "destroy requires authentication" do
        delete api_v1_activity_path(@note_activity), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # COMPLETE Tests
      # ====================================================================

      test "should complete activity" do
        post complete_api_v1_activity_path(@task_activity), params: {
          outcome: "Task completed successfully"
        }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert_equal "completed", response_body["activity"]["status"]

        @task_activity.reload
        assert_equal "completed", @task_activity.status
        assert_not_nil @task_activity.completed_at
      end

      # ====================================================================
      # CANCEL Tests
      # ====================================================================

      test "should cancel activity" do
        post cancel_api_v1_activity_path(@task_activity), params: {
          reason: "No longer needed"
        }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert_equal "cancelled", response_body["activity"]["status"]
      end
    end
  end
end
