# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class TasksControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @entity = entities(:one)
        @user.update!(entity: @entity, api_key: SecureRandom.hex(32))

        # Create test task sessions (use valid enum values: autonomous, interactive, hybrid)
        # Status values: active, completed, failed, cancelled, paused
        @task = TaskSession.create!(
          user: @user,
          session_type: "autonomous",
          status: "active",
          metadata: { title: "Test Task", description: "A test task description" }
        )

        @completed_task = TaskSession.create!(
          user: @user,
          session_type: "interactive",
          status: "completed",
          metadata: { title: "Completed Task", description: "A completed task" }
        )
      end

      teardown do
        TaskSession.where(user: @user).destroy_all
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

      test "should get tasks list with valid token" do
        get api_v1_tasks_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("data")
        assert response_body.key?("pagination")
      end

      test "tasks list returns expected fields" do
        get api_v1_tasks_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        tasks = response_body["data"]

        assert tasks.any?

        task = tasks.find { |t| t["id"] == @task.id }
        assert_not_nil task
        assert_equal "Test Task", task["title"]
        assert_equal "A test task description", task["description"]
        assert_equal "active", task["status"]
        assert task.key?("created_at")
        assert task.key?("updated_at")
      end

      test "tasks list includes pagination info" do
        get api_v1_tasks_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        pagination = response_body["pagination"]

        assert pagination.key?("current_page")
        assert pagination.key?("total_pages")
        assert pagination.key?("total_count")
        assert pagination.key?("per_page")
      end

      test "tasks list can be filtered by status" do
        get api_v1_tasks_path, params: { status: "completed" }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        tasks = response_body["data"]

        task_ids = tasks.map { |t| t["id"] }
        assert_includes task_ids, @completed_task.id
        assert_not_includes task_ids, @task.id
      end

      test "tasks list supports pagination params" do
        get api_v1_tasks_path, params: { page: 1, per_page: 1 }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal 1, response_body["pagination"]["per_page"]
        assert_equal 1, response_body["data"].size
      end

      test "tasks list requires authentication" do
        get api_v1_tasks_path, as: :json

        assert_response :unauthorized
      end

      test "tasks list rejects invalid token" do
        get api_v1_tasks_path,
          headers: { "Authorization" => "Bearer invalid_token" },
          as: :json

        assert_response :unauthorized
      end

      test "tasks list only returns current user tasks" do
        other_user = users(:two)
        other_user.update!(entity: entities(:two), api_key: SecureRandom.hex(32))

        other_task = TaskSession.create!(
          user: other_user,
          session_type: "autonomous",
          status: "active",
          metadata: { title: "Other User Task" }
        )

        get api_v1_tasks_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        task_ids = response_body["data"].map { |t| t["id"] }

        assert_not_includes task_ids, other_task.id

        other_task.destroy
      end

      # ====================================================================
      # SHOW Tests
      # ====================================================================

      test "should get task details with valid token" do
        get api_v1_task_path(@task), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal @task.id, response_body["id"]
        assert_equal "Test Task", response_body["title"]
        assert_equal "A test task description", response_body["description"]
      end

      test "task details include wizard_data and artifacts" do
        @task.update!(wizard_data: { step: 1 }, artifacts: [{ type: "file", name: "test.txt" }])

        get api_v1_task_path(@task), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("wizard_data")
        assert response_body.key?("artifacts")
      end

      test "should return 404 for non-existent task" do
        get api_v1_task_path(id: 999999), headers: auth_headers, as: :json

        assert_response :not_found
      end

      test "should return 404 for other user task" do
        other_user = users(:two)
        other_user.update!(entity: entities(:two), api_key: SecureRandom.hex(32))

        other_task = TaskSession.create!(
          user: other_user,
          session_type: "autonomous",
          status: "active",
          metadata: { title: "Other User Task" }
        )

        get api_v1_task_path(other_task), headers: auth_headers, as: :json

        assert_response :not_found

        other_task.destroy
      end

      test "task show requires authentication" do
        get api_v1_task_path(@task), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # CREATE Tests
      # ====================================================================

      test "should create task with valid params" do
        assert_difference("TaskSession.count", 1) do
          post api_v1_tasks_path, params: {
            title: "New Task",
            description: "New task description"
          }, headers: auth_headers, as: :json
        end

        assert_response :created

        response_body = JSON.parse(response.body)
        assert_equal "New Task", response_body["title"]
        assert_equal "New task description", response_body["description"]
      end

      test "created task belongs to current user" do
        post api_v1_tasks_path, params: {
          title: "User Task"
        }, headers: auth_headers, as: :json

        assert_response :created

        created_task = TaskSession.order(created_at: :desc).first
        assert_equal @user.id, created_task.user_id
      end

      test "create task requires authentication" do
        post api_v1_tasks_path, params: {
          title: "New Task"
        }, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # UPDATE Tests
      # ====================================================================

      test "should update task with valid params" do
        patch api_v1_task_path(@task), params: {
          title: "Updated Task",
          status: "paused"
        }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal "Updated Task", response_body["title"]
        assert_equal "paused", response_body["status"]
      end

      test "should not update other user task" do
        other_user = users(:two)
        other_user.update!(entity: entities(:two), api_key: SecureRandom.hex(32))

        other_task = TaskSession.create!(
          user: other_user,
          session_type: "autonomous",
          status: "active",
          metadata: { title: "Other User Task" }
        )

        patch api_v1_task_path(other_task), params: {
          title: "Hacked Task"
        }, headers: auth_headers, as: :json

        assert_response :not_found

        other_task.destroy
      end

      test "update task requires authentication" do
        patch api_v1_task_path(@task), params: {
          title: "Updated Task"
        }, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # DESTROY Tests
      # ====================================================================

      test "should destroy task" do
        assert_difference("TaskSession.count", -1) do
          delete api_v1_task_path(@task), headers: auth_headers, as: :json
        end

        assert_response :no_content
      end

      test "should not destroy other user task" do
        other_user = users(:two)
        other_user.update!(entity: entities(:two), api_key: SecureRandom.hex(32))

        other_task = TaskSession.create!(
          user: other_user,
          session_type: "autonomous",
          status: "active",
          metadata: { title: "Other User Task" }
        )

        assert_no_difference("TaskSession.count") do
          delete api_v1_task_path(other_task), headers: auth_headers, as: :json
        end

        assert_response :not_found

        other_task.destroy
      end

      test "destroy task requires authentication" do
        delete api_v1_task_path(@task), as: :json

        assert_response :unauthorized
      end
    end
  end
end
