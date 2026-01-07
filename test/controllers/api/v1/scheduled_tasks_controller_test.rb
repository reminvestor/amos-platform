# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class ScheduledTasksControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @entity = entities(:one)
        @user.update!(entity: @entity, api_key: SecureRandom.hex(32))

        # Create test scheduled tasks
        @task = ScheduledAgentTask.create!(
          entity: @entity,
          user: @user,
          name: "Test Daily Task",
          description: "A test daily scheduled task",
          task_type: "email_summary",
          prompt: "Generate a daily email summary",
          schedule_type: "daily",
          run_at_time: "09:00",
          timezone: "UTC",
          status: "active",
          enabled: true
        )

        @paused_task = ScheduledAgentTask.create!(
          entity: @entity,
          user: @user,
          name: "Paused Task",
          description: "A paused scheduled task",
          task_type: "report_generation",
          prompt: "Generate weekly report",
          schedule_type: "weekly",
          run_at_time: "10:00",
          run_on_day: 1,
          timezone: "UTC",
          status: "paused",
          enabled: false
        )
      end

      teardown do
        ScheduledAgentTask.where(user: @user).destroy_all
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

      test "should get scheduled tasks list with valid token" do
        get api_v1_scheduled_tasks_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("data")
        assert response_body.key?("pagination")
        assert response_body.key?("counts")
      end

      test "scheduled tasks list returns expected fields" do
        get api_v1_scheduled_tasks_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        tasks = response_body["data"]

        assert tasks.any?

        task = tasks.find { |t| t["id"] == @task.id }
        assert_not_nil task
        assert_equal "Test Daily Task", task["name"]
        assert_equal "email_summary", task["task_type"]
        assert_equal "daily", task["schedule_type"]
        assert_equal "active", task["status"]
        assert task.key?("next_run_at")
        assert task.key?("can_run")
      end

      test "scheduled tasks list can filter by status" do
        get api_v1_scheduled_tasks_path, params: { status: "paused" }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        task_ids = response_body["data"].map { |t| t["id"] }

        assert_not_includes task_ids, @task.id
        assert_includes task_ids, @paused_task.id
      end

      test "scheduled tasks list can filter by task_type" do
        get api_v1_scheduled_tasks_path, params: { task_type: "email_summary" }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        task_ids = response_body["data"].map { |t| t["id"] }

        assert_includes task_ids, @task.id
        assert_not_includes task_ids, @paused_task.id
      end

      test "scheduled tasks list requires authentication" do
        get api_v1_scheduled_tasks_path, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # SHOW Tests
      # ====================================================================

      test "should get scheduled task details with valid token" do
        get api_v1_scheduled_task_path(@task), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal @task.id, response_body["id"]
        assert_equal "Test Daily Task", response_body["name"]
        assert_equal "Generate a daily email summary", response_body["prompt"]
      end

      test "should return 404 for non-existent task" do
        get api_v1_scheduled_task_path(id: 999999), headers: auth_headers, as: :json

        assert_response :not_found
      end

      test "scheduled task show requires authentication" do
        get api_v1_scheduled_task_path(@task), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # CREATE Tests
      # ====================================================================

      test "should create scheduled task with valid params" do
        assert_difference("ScheduledAgentTask.count", 1) do
          post api_v1_scheduled_tasks_path, params: {
            name: "New Scheduled Task",
            description: "A new task",
            task_type: "custom",
            prompt: "Do something custom",
            schedule_type: "daily",
            run_at_time: "14:00",
            timezone: "America/New_York"
          }, headers: auth_headers, as: :json
        end

        assert_response :created

        response_body = JSON.parse(response.body)
        assert_equal "New Scheduled Task", response_body["name"]
      end

      test "create returns error for missing required params" do
        post api_v1_scheduled_tasks_path, params: {
          name: "Incomplete Task"
          # Missing task_type, prompt, schedule_type
        }, headers: auth_headers, as: :json

        assert_response :unprocessable_entity

        response_body = JSON.parse(response.body)
        assert response_body["errors"].any?
      end

      test "create requires authentication" do
        post api_v1_scheduled_tasks_path, params: {
          name: "New Task",
          task_type: "custom",
          prompt: "Test",
          schedule_type: "daily",
          run_at_time: "09:00"
        }, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # UPDATE Tests
      # ====================================================================

      test "should update scheduled task with valid params" do
        patch api_v1_scheduled_task_path(@task), params: {
          name: "Updated Task Name",
          description: "Updated description"
        }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal "Updated Task Name", response_body["name"]

        @task.reload
        assert_equal "Updated Task Name", @task.name
      end

      test "update requires authentication" do
        patch api_v1_scheduled_task_path(@task), params: {
          name: "Hacked"
        }, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # DESTROY Tests
      # ====================================================================

      test "should archive scheduled task (soft delete)" do
        delete api_v1_scheduled_task_path(@task), headers: auth_headers, as: :json

        assert_response :no_content

        @task.reload
        assert_equal "archived", @task.status
      end

      test "destroy requires authentication" do
        delete api_v1_scheduled_task_path(@task), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # PAUSE Tests
      # ====================================================================

      test "should pause active task" do
        post pause_api_v1_scheduled_task_path(@task), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal "paused", response_body["status"]

        @task.reload
        assert_equal "paused", @task.status
      end

      test "pause requires authentication" do
        post pause_api_v1_scheduled_task_path(@task), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # RESUME Tests
      # ====================================================================

      test "should resume paused task" do
        post resume_api_v1_scheduled_task_path(@paused_task), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal "active", response_body["status"]

        @paused_task.reload
        assert_equal "active", @paused_task.status
      end

      test "resume requires authentication" do
        post resume_api_v1_scheduled_task_path(@paused_task), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # RUN_NOW Tests
      # ====================================================================

      test "run_now queues task for execution" do
        post run_now_api_v1_scheduled_task_path(@task), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body["message"].include?("queued")
      end

      test "run_now requires authentication" do
        post run_now_api_v1_scheduled_task_path(@task), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # TASK_TYPES Tests
      # ====================================================================

      test "should get available task types" do
        get task_types_api_v1_scheduled_tasks_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("data")

        task_types = response_body["data"]
        assert task_types.any?

        type_ids = task_types.map { |t| t["id"] }
        assert_includes type_ids, "email_summary"
        assert_includes type_ids, "custom"
      end

      test "task_types requires authentication" do
        get task_types_api_v1_scheduled_tasks_path, as: :json

        assert_response :unauthorized
      end
    end
  end
end
