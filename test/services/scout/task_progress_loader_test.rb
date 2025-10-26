require "test_helper"

module Scout
  class TaskProgressLoaderTest < ActiveSupport::TestCase
    def setup
      @user = users(:one)
      @session_id = SecureRandom.uuid
      @loader = Scout::TaskProgressLoader.new(user: @user, session_id: @session_id)
    end

    # is_workflow_approval? tests
    test "is_workflow_approval? returns true when awaiting_approval is set" do
      data = { awaiting_approval: true }

      assert @loader.is_workflow_approval?(data)
    end

    test "is_workflow_approval? returns true for string key" do
      data = { "awaiting_approval" => true }

      assert @loader.is_workflow_approval?(data)
    end

    test "is_workflow_approval? returns false when not awaiting approval" do
      data = { message: "test" }

      refute @loader.is_workflow_approval?(data)
    end

    test "is_workflow_approval? returns false for empty data" do
      assert_equal false, @loader.is_workflow_approval?({})
    end

    # load_task_data tests - empty/nil scenarios
    test "load_task_data returns empty tasks when no data and no task session" do
      result = @loader.load_task_data({})

      assert_equal [], result[:tasks]
    end

    test "load_task_data returns empty tasks when nil data and no task session" do
      result = @loader.load_task_data(nil)

      assert result[:tasks].is_a?(Array)
    end

    # load_task_data tests - with provided data
    test "load_task_data returns provided data when tasks present" do
      provided_data = {
        tasks: [
          { id: 1, description: "Task 1", status: "completed" },
          { id: 2, description: "Task 2", status: "pending" }
        ]
      }

      result = @loader.load_task_data(provided_data)

      assert_equal 2, result[:tasks].length
      assert_equal "Task 1", result[:tasks][0][:description]
      assert_equal "Task 2", result[:tasks][1][:description]
    end

    test "load_task_data handles string keys" do
      provided_data = {
        "tasks" => [
          { "id" => 1, "description" => "Task 1" }
        ]
      }

      result = @loader.load_task_data(provided_data)

      assert_equal 1, result[:tasks].length
    end

    test "load_task_data does not load from session when awaiting_approval" do
      # Create a task session
      task_session = TaskSession.create!(
        user: @user,
        status: "active",
        metadata: { "session_id" => @session_id },
        state: {
          "task_list" => {
            tasks: [{ id: 1, description: "Should not load" }]
          }
        }
      )

      data = { awaiting_approval: true }

      result = @loader.load_task_data(data)

      # Should not load from task session
      assert_nil result[:tasks]
    end

    # load_task_data tests - from TaskSession state
    test "load_task_data loads from TaskSession state when available" do
      task_list = {
        tasks: [
          { id: 1, description: "Task from state", status: "completed" }
        ]
      }

      ts = TaskSession.create!(
        user: @user,
        status: "active",
        metadata: { "session_id" => @session_id },
        state: { "task_list" => task_list }
      )

      # Verify TaskSession was created correctly
      assert ts.persisted?, "TaskSession should be persisted"
      assert_equal "active", ts.status, "TaskSession should have active status"
      assert_equal @session_id, ts.metadata["session_id"], "TaskSession should have correct session_id"
      assert_not_nil ts.state["task_list"], "TaskSession should have task_list in state"

      # Verify we can find it with the same query the loader uses
      found = TaskSession.active.where(user: @user).where("metadata->>'session_id' = ?", @session_id).first
      assert_not_nil found, "Should be able to find TaskSession with loader query"

      result = @loader.load_task_data({})

      assert result[:tasks].present?, "Expected tasks to be present but got nil"
      assert_equal 1, result[:tasks].length
      assert_equal "Task from state", result[:tasks][0][:description]
    end

    test "load_task_data loads from specific task_session_id" do
      # Create two task sessions
      task_session_1 = TaskSession.create!(
        user: @user,
        status: "active",
        state: {
          "task_list" => {
            tasks: [{ id: 1, description: "Task 1" }]
          }
        }
      )

      task_session_2 = TaskSession.create!(
        user: @user,
        status: "active",
        state: {
          "task_list" => {
            tasks: [{ id: 2, description: "Task 2" }]
          }
        }
      )

      # Load specific session
      result = @loader.load_task_data(task_session_id: task_session_2.id)

      assert_equal 1, result[:tasks].length
      assert_equal "Task 2", result[:tasks][0][:description]
    end

    test "load_task_data with string task_session_id key" do
      task_session = TaskSession.create!(
        user: @user,
        status: "active",
        state: {
          "task_list" => {
            tasks: [{ id: 1, description: "Test" }]
          }
        }
      )

      result = @loader.load_task_data("task_session_id" => task_session.id)

      assert_equal 1, result[:tasks].length
    end

    # load_task_data tests - from workflow spec
    # NOTE: Workflow-related tests require complex setup - covered by integration tests
    test "load_task_data converts workflow to task list when no state" do
      skip "Workflow tests covered by integration tests"
      workflow_spec = {
        "id" => "test_workflow",
        "steps" => [
          {
            "id" => "step1",
            "name" => "First Step",
            "description" => "First step description",
            "type" => "tool",
            "tool" => "get_data"
          }
        ]
      }

      task_session = TaskSession.create!(
        user: @user,
        status: "active",
        metadata: { "session_id" => @session_id },
        workflow_spec: workflow_spec
      )

      # Mock WorkflowEngine
      mock_workflow = mock('workflow')
      mock_step = mock('step')
      mock_step.stubs(:id).returns("step1")
      mock_step.stubs(:name).returns("First Step")
      mock_step.stubs(:description).returns("First step description")
      mock_step.stubs(:config).returns({ name: "First Step", description: "First step description" })
      mock_step.stubs(:status).returns("pending")
      mock_step.stubs(:completed_at).returns(nil)
      mock_workflow.stubs(:steps).returns([mock_step])

      mock_engine = mock('workflow_engine')
      mock_engine.stubs(:progress).returns({ status: "in_progress" })
      mock_engine.stubs(:instance_variable_get).with(:@workflow).returns(mock_workflow)

      WorkflowEngine.stubs(:new).returns(mock_engine)

      result = @loader.load_task_data({})

      assert_equal 1, result[:tasks].length
      assert_equal "step1", result[:tasks][0][:id]
      assert_equal "First Step", result[:tasks][0][:description]
      assert_equal "pending", result[:tasks][0][:status]
      assert_equal "in_progress", result[:workflow_status]
    end

    # convert_workflow_progress_to_tasks tests
    test "convert_workflow_progress_to_tasks converts progress with task_session_id" do
      skip "Workflow tests covered by integration tests"
      workflow_spec = {
        "id" => "test_workflow",
        "steps" => [
          {
            "id" => "step1",
            "type" => "tool",
            "tool" => "test"
          }
        ]
      }

      task_session = TaskSession.create!(
        user: @user,
        workflow_name: "Test Workflow",
        workflow_spec: workflow_spec
      )

      # Mock WorkflowEngine
      mock_workflow = mock('workflow')
      mock_step = mock('step')
      mock_step.stubs(:id).returns("step1")
      mock_step.stubs(:config).returns({ description: "Test Step" })
      mock_step.stubs(:status).returns("completed")
      mock_step.stubs(:error).returns(nil)
      mock_step.stubs(:completed_at).returns(Time.current)
      mock_workflow.stubs(:steps).returns([mock_step])

      mock_engine = mock('workflow_engine')
      mock_engine.stubs(:instance_variable_get).with(:@workflow).returns(mock_workflow)

      WorkflowEngine.stubs(:new).returns(mock_engine)

      data = {
        progress: { status: "completed" },
        task_session_id: task_session.id
      }

      result = @loader.load_task_data(data)

      assert_equal 1, result[:tasks].length
      assert_equal "Test Step", result[:tasks][0][:description]
      assert_equal "completed", result[:tasks][0][:status]
      assert_equal "Test Workflow", result[:title]
    end

    test "convert_workflow_progress_to_tasks returns empty tasks without task_session_id" do
      data = {
        progress: { status: "completed" },
        some_field: "value"
      }

      result = @loader.load_task_data(data)

      # Without task_session_id and no active task session, returns empty tasks
      assert_equal [], result[:tasks]
    end

    # convert_workflow_to_task_list tests
    test "convert_workflow_to_task_list includes workflow_status and progress" do
      skip "Workflow tests covered by integration tests"
      workflow_spec = {
        "id" => "test",
        "steps" => [{ "id" => "step1", "type" => "tool" }]
      }

      task_session = TaskSession.create!(
        user: @user,
        status: "active",
        metadata: { "session_id" => @session_id },
        workflow_spec: workflow_spec
      )

      # Mock workflow
      mock_workflow = mock('workflow')
      mock_step = mock('step')
      mock_step.stubs(:id).returns("step1")
      mock_step.stubs(:name).returns("Step 1")
      mock_step.stubs(:description).returns("Step 1 desc")
      mock_step.stubs(:config).returns({ name: "Step 1", description: "Step 1 desc" })
      mock_step.stubs(:status).returns("pending")
      mock_step.stubs(:completed_at).returns(nil)
      mock_workflow.stubs(:steps).returns([mock_step])

      mock_engine = mock('workflow_engine')
      mock_progress = { status: "running", completed_steps: 0 }
      mock_engine.stubs(:progress).returns(mock_progress)
      mock_engine.stubs(:instance_variable_get).with(:@workflow).returns(mock_workflow)

      WorkflowEngine.stubs(:new).returns(mock_engine)

      result = @loader.load_task_data({})

      assert_equal "running", result[:workflow_status]
      assert_equal 0, result[:progress][:completed_steps]
    end

    test "convert_workflow_to_task_list uses workflow_execution status when available" do
      skip "Workflow tests covered by integration tests"
      workflow_spec = {
        "id" => "test",
        "steps" => [{ "id" => "step1", "type" => "tool" }]
      }

      task_session = TaskSession.create!(
        user: @user,
        status: "active",
        metadata: { "session_id" => @session_id },
        workflow_spec: workflow_spec
      )

      # Create workflow execution
      workflow_execution = WorkflowExecution.create!(
        entity: entities(:one),
        user: @user,
        workflow_name: "Test"
      )

      # Create step execution
      step_execution = WorkflowStepExecution.create!(
        workflow_execution: workflow_execution,
        step_id: "step1",
        step_type: "tool",
        status: "completed",
        completed_at: Time.current
      )

      task_session.update!(workflow_execution: workflow_execution)

      # Mock workflow with pending status
      mock_workflow = mock('workflow')
      mock_step = mock('step')
      mock_step.stubs(:id).returns("step1")
      mock_step.stubs(:name).returns("Step 1")
      mock_step.stubs(:description).returns("Step 1 desc")
      mock_step.stubs(:config).returns({})
      mock_step.stubs(:status).returns("pending") # Should be overridden
      mock_step.stubs(:completed_at).returns(nil) # Should be overridden
      mock_workflow.stubs(:steps).returns([mock_step])

      mock_engine = mock('workflow_engine')
      mock_engine.stubs(:progress).returns({ status: "running" })
      mock_engine.stubs(:instance_variable_get).with(:@workflow).returns(mock_workflow)

      WorkflowEngine.stubs(:new).returns(mock_engine)

      result = @loader.load_task_data({})

      # Should use status from workflow_execution, not workflow step
      assert_equal "completed", result[:tasks][0][:status]
      assert_not_nil result[:tasks][0][:completed_at]
    end

    test "convert_workflow_to_task_list sets failed_at when status is failed" do
      skip "Workflow tests covered by integration tests"
      workflow_spec = {
        "id" => "test",
        "steps" => [{ "id" => "step1", "type" => "tool" }]
      }

      task_session = TaskSession.create!(
        user: @user,
        status: "active",
        metadata: { "session_id" => @session_id },
        workflow_spec: workflow_spec
      )

      # Mock workflow with failed step
      mock_workflow = mock('workflow')
      mock_step = mock('step')
      failed_time = Time.current
      mock_step.stubs(:id).returns("step1")
      mock_step.stubs(:name).returns("Step 1")
      mock_step.stubs(:description).returns("Step 1 desc")
      mock_step.stubs(:config).returns({})
      mock_step.stubs(:status).returns("failed")
      mock_step.stubs(:completed_at).returns(failed_time)
      mock_workflow.stubs(:steps).returns([mock_step])

      mock_engine = mock('workflow_engine')
      mock_engine.stubs(:progress).returns({ status: "failed" })
      mock_engine.stubs(:instance_variable_get).with(:@workflow).returns(mock_workflow)

      WorkflowEngine.stubs(:new).returns(mock_engine)

      result = @loader.load_task_data({})

      assert_equal "failed", result[:tasks][0][:status]
      assert_equal failed_time, result[:tasks][0][:failed_at]
    end

    # Edge cases
    test "load_task_data handles TaskSession without user match" do
      other_user = users(:two)

      TaskSession.create!(
        user: other_user,
        status: "active",
        metadata: { "session_id" => @session_id },
        state: {
          "task_list" => {
            tasks: [{ id: 1, description: "Other user's task" }]
          }
        }
      )

      result = @loader.load_task_data({})

      # Should not load other user's task
      assert_equal [], result[:tasks]
    end

    test "load_task_data handles inactive TaskSession" do
      TaskSession.create!(
        user: @user,
        status: "completed", # Not active
        metadata: { "session_id" => @session_id },
        state: {
          "task_list" => {
            tasks: [{ id: 1, description: "Completed task" }]
          }
        }
      )

      result = @loader.load_task_data({})

      # Should not load from completed session
      assert_equal [], result[:tasks]
    end

    test "load_task_data handles TaskSession with neither state nor workflow_spec" do
      TaskSession.create!(
        user: @user,
        status: "active",
        metadata: { "session_id" => @session_id },
        state: nil,
        workflow_spec: nil
      )

      result = @loader.load_task_data({})

      assert_equal [], result[:tasks]
    end
  end
end
