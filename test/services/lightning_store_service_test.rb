require "test_helper"

class LightningStoreServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @workflow_execution = workflow_executions(:one)
    @task_session = task_sessions(:one)
    @service = LightningStoreService.new(@entity, @user)
  end

  test "should initialize service with entity and user" do
    assert_equal @entity, @service.entity
    assert_equal @user, @service.user
  end

  test "should start workflow trace" do
    trace = @service.start_workflow_trace(@workflow_execution, @task_session, "Create a landing page")

    assert trace.persisted?
    assert_equal @entity, trace.entity
    assert_equal @user, trace.user
    assert_equal "workflow", trace.trace_type
    assert_equal "pending", trace.status
  end

  test "should record llm call" do
    @service.start_workflow_trace(@workflow_execution, @task_session, "test")

    call = @service.record_llm_call(
      model: "claude-sonnet-4-5",
      agent_role: "executor",
      system_prompt: { instructions: "test" },
      user_messages: [{ role: "user", content: "test" }],
      response_content: { text: "response" },
      input_tokens: 100,
      output_tokens: 50,
      latency_ms: 1000,
      status: "success"
    )

    assert call.persisted?
    assert_equal "claude-sonnet-4-5", call.model
    assert_equal "executor", call.agent_role
    assert_equal 150, call.total_tokens
  end

  test "should update trace with token count and cost" do
    trace = @service.start_workflow_trace(@workflow_execution, @task_session, "test")
    initial_token_count = trace.token_count || 0

    @service.record_llm_call(
      model: "claude-sonnet-4-5",
      agent_role: "executor",
      system_prompt: {},
      user_messages: [],
      response_content: {},
      input_tokens: 100,
      output_tokens: 50,
      latency_ms: 1000,
      status: "success"
    )

    trace.reload
    assert_equal initial_token_count + 150, trace.token_count
  end

  test "should record tool execution" do
    @service.start_workflow_trace(@workflow_execution, @task_session, "test")

    execution = @service.record_tool_execution(
      tool_name: "generate_ai_landing_page",
      tool_category: "content_generation",
      input_arguments: { title: "My App" },
      output_result: { page_id: "123", success: true },
      status: "success",
      execution_time_ms: 5000
    )

    assert execution.persisted?
    assert_equal "generate_ai_landing_page", execution.tool_name
    assert_equal "content_generation", execution.tool_category
    assert_equal "success", execution.status
  end

  test "should record phase execution" do
    @service.start_workflow_trace(@workflow_execution, @task_session, "test")

    phase = @service.record_phase_execution(
      phase_id: "gather_context",
      phase_type: "gather_context",
      workflow_execution: @workflow_execution,
      phase_input: { data: "test" },
      status: "running"
    )

    assert phase.persisted?
    assert_equal "gather_context", phase.phase_id
    assert_equal @workflow_execution, phase.workflow_execution
  end

  test "should add intermediate steps" do
    trace = @service.start_workflow_trace(@workflow_execution, @task_session, "test")

    @service.add_step(step_description: "Gathering context", status: "success")
    @service.add_step(step_description: "Executing tools", status: "running")

    trace.reload
    assert_equal 2, trace.intermediate_steps.count
    assert_equal "Gathering context", trace.intermediate_steps.first[:step]
  end

  test "should complete trace" do
    trace = @service.start_workflow_trace(@workflow_execution, @task_session, "test")

    @service.complete_trace(
      output_data: { result: "success" },
      duration_ms: 5000,
      status: "completed"
    )

    trace.reload
    assert_equal "completed", trace.status
    assert_equal 5000, trace.duration_ms
    assert_equal({ result: "success" }, trace.output_data)
  end

  test "should record reward signal" do
    trace = @service.start_workflow_trace(@workflow_execution, @task_session, "test")

    reward = @service.record_reward(
      reward_type: "completion",
      reward_value: 0.85,
      source: "automated",
      reason: "Task completed successfully"
    )

    assert reward.persisted?
    assert_equal 0.85, reward.reward_value
    assert_equal "completion", reward.reward_type

    trace.reload
    assert_equal 0.85, trace.reward_signal
  end

  test "should mark trace as training_ready" do
    trace = @service.start_workflow_trace(@workflow_execution, @task_session, "test")

    @service.mark_training_ready

    trace.reload
    assert trace.included_in_training
    assert_equal "training_ready", trace.status
  end

  test "should get current trace" do
    trace = @service.start_workflow_trace(@workflow_execution, @task_session, "test")

    assert_equal trace, @service.current_trace
  end

  test "should handle missing trace gracefully" do
    service = LightningStoreService.new(@entity, @user)
    # Don't start a trace

    call = service.record_llm_call(
      model: "claude-sonnet-4-5",
      agent_role: "executor",
      system_prompt: {},
      user_messages: [],
      response_content: {},
      input_tokens: 100,
      output_tokens: 50,
      latency_ms: 1000
    )

    assert_nil call
  end

  test "should get or create default config" do
    config = @service.get_config

    assert config
    assert config.enabled
    assert_equal "observing", config.mode
  end

  test "should calculate token cost for different models" do
    @service.start_workflow_trace(@workflow_execution, @task_session, "test")

    # Test Sonnet 4.5 pricing
    cost_sonnet = @service.calculate_token_cost("claude-sonnet-4-5", 1_000_000, 1_000_000)
    assert_in_delta 18.0, cost_sonnet, 0.1

    # Test Haiku pricing
    cost_haiku = @service.calculate_token_cost("claude-haiku-4.5", 1_000_000, 1_000_000)
    assert_in_delta 4.8, cost_haiku, 0.1

    # Test unknown model
    cost_unknown = @service.calculate_token_cost("unknown-model", 1000, 1000)
    assert_equal 0, cost_unknown
  end

  test "should check if training should run" do
    # Entity without config - should create default
    should_train = @service.should_train?

    # New entity with no traces won't be ready for training
    assert_not should_train
  end

  test "should get training data" do
    # Create multiple traces with rewards
    3.times do
      trace = @service.start_workflow_trace(@workflow_execution, @task_session, "test")
      @service.record_llm_call(
        model: "claude-sonnet-4-5",
        agent_role: "executor",
        system_prompt: {},
        user_messages: [],
        response_content: {},
        input_tokens: 100,
        output_tokens: 50,
        latency_ms: 1000
      )
      @service.record_reward(reward_type: "completion", reward_value: 0.8, source: "automated")
      @service.complete_trace(output_data: { result: "success" }, duration_ms: 2000)
    end

    training_data = @service.get_training_data
    assert_equal 3, training_data.count
    assert training_data.first.key?(:llm_calls)
    assert training_data.first.key?(:reward)
  end
end
