require "test_helper"

class AgentLightningEdgeCasesTest < ActionDispatch::IntegrationTest
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @workflow_execution = workflow_executions(:one)
    @task_session = task_sessions(:one)

    @entity.create_agent_lightning_config!(
      enabled: true,
      mode: "optimizing",
      training_strategy: "prompt_optimization",
      min_traces_for_training: 2
    ) unless @entity.agent_lightning_config
  end

  test "handles trace without rewards gracefully" do
    lightning_store = LightningStoreService.new(@entity, @user)
    trace = lightning_store.start_workflow_trace(
      @workflow_execution,
      @task_session,
      "test"
    )

    lightning_store.record_llm_call(
      model: "claude-sonnet-4-5",
      agent_role: "executor",
      system_prompt: {},
      user_messages: [],
      response_content: {},
      input_tokens: 100,
      output_tokens: 50,
      latency_ms: 1000
    )

    lightning_store.complete_trace(output_data: { result: "success" })

    # Don't record reward - trace should still exist but not be used for training
    trace.reload
    assert_equal "completed", trace.status
    assert_nil trace.reward_signal
  end

  test "handles concurrent trace collection" do
    lightning_store1 = LightningStoreService.new(@entity, @user)
    lightning_store2 = LightningStoreService.new(@entity, @user)

    trace1 = lightning_store1.start_workflow_trace(
      @workflow_execution,
      @task_session,
      "request 1"
    )

    trace2 = lightning_store2.start_workflow_trace(
      @workflow_execution,
      @task_session,
      "request 2"
    )

    assert_not_equal trace1.id, trace2.id
    assert_equal 2, @entity.agent_lightning_traces.count
  end

  test "handles large token count tracking" do
    lightning_store = LightningStoreService.new(@entity, @user)
    trace = lightning_store.start_workflow_trace(
      @workflow_execution,
      @task_session,
      "test"
    )

    # Record multiple calls with large token counts
    5.times do
      lightning_store.record_llm_call(
        model: "claude-sonnet-4-5",
        agent_role: "executor",
        system_prompt: {},
        user_messages: [],
        response_content: {},
        input_tokens: 10000,
        output_tokens: 5000,
        latency_ms: 2000
      )
    end

    lightning_store.complete_trace(output_data: { result: "success" })

    trace.reload
    assert_equal 75000, trace.token_count  # 5 * (10000 + 5000)
  end

  test "handles high-frequency reward updates" do
    lightning_store = LightningStoreService.new(@entity, @user)
    trace = lightning_store.start_workflow_trace(
      @workflow_execution,
      @task_session,
      "test"
    )

    lightning_store.record_llm_call(
      model: "claude-sonnet-4-5",
      agent_role: "executor",
      system_prompt: {},
      user_messages: [],
      response_content: {},
      input_tokens: 100,
      output_tokens: 50,
      latency_ms: 1000
    )

    # Record multiple rewards - should keep the highest
    lightning_store.record_reward(reward_type: "completion", reward_value: 0.5, source: "automated")
    lightning_store.record_reward(reward_type: "quality", reward_value: 0.9, source: "user")
    lightning_store.record_reward(reward_type: "efficiency", reward_value: 0.7, source: "automated")

    lightning_store.complete_trace(output_data: { result: "success" })

    trace.reload
    assert_equal 0.9, trace.reward_signal  # Highest reward
    assert_equal 3, trace.agent_rewards.count
  end

  test "handles training with minimum required traces" do
    training_service = AgentLightningTrainingService.new(@entity)

    # Create exactly minimum traces
    2.times do
      lightning_store = LightningStoreService.new(@entity, @user)
      trace = lightning_store.start_workflow_trace(
        @workflow_execution,
        @task_session,
        "test"
      )
      lightning_store.record_llm_call(
        model: "claude-sonnet-4-5",
        agent_role: "executor",
        system_prompt: {},
        user_messages: [],
        response_content: {},
        input_tokens: 100,
        output_tokens: 50,
        latency_ms: 1000
      )
      lightning_store.record_reward(reward_type: "completion", reward_value: 0.8, source: "automated")
      lightning_store.complete_trace(output_data: { result: "success" })
    end

    result = training_service.execute_training

    assert result[:success]
    assert_equal 2, result[:traces_used]
  end

  test "handles training with no traces" do
    training_service = AgentLightningTrainingService.new(@entity)

    result = training_service.execute_training([])

    assert_not result[:success]
    assert result.key?(:error)
  end

  test "handles bedrock error during trace recording" do
    lightning_store = LightningStoreService.new(@entity, @user)
    trace = lightning_store.start_workflow_trace(
      @workflow_execution,
      @task_session,
      "test"
    )

    # Record failed LLM call
    call = lightning_store.record_llm_call(
      model: "claude-sonnet-4-5",
      agent_role: "executor",
      system_prompt: {},
      user_messages: [],
      response_content: nil,
      input_tokens: 0,
      output_tokens: 0,
      latency_ms: 3000,
      status: "error",
      error_message: "ThrottlingException: Rate limit exceeded"
    )

    assert call.persisted?
    assert_equal "error", call.status
    assert call.error_message.present?
  end

  test "handles trace with zero duration" do
    lightning_store = LightningStoreService.new(@entity, @user)
    trace = lightning_store.start_workflow_trace(
      @workflow_execution,
      @task_session,
      "test"
    )

    lightning_store.record_llm_call(
      model: "claude-sonnet-4-5",
      agent_role: "executor",
      system_prompt: {},
      user_messages: [],
      response_content: {},
      input_tokens: 100,
      output_tokens: 50,
      latency_ms: 0  # Edge case: zero latency
    )

    lightning_store.complete_trace(output_data: { result: "success" }, duration_ms: 0)

    trace.reload
    assert_equal 0, trace.duration_ms
  end

  test "handles trace with empty input/output data" do
    lightning_store = LightningStoreService.new(@entity, @user)
    trace = lightning_store.start_workflow_trace(
      @workflow_execution,
      @task_session,
      ""  # Empty request
    )

    lightning_store.record_llm_call(
      model: "claude-sonnet-4-5",
      agent_role: "executor",
      system_prompt: {},
      user_messages: [],
      response_content: {},  # Empty response
      input_tokens: 0,
      output_tokens: 0,
      latency_ms: 100
    )

    lightning_store.complete_trace(output_data: {})  # Empty output

    trace.reload
    assert_equal({}, trace.input_data.merge(trace.output_data))
  end

  test "handles duplicate trace_id prevention" do
    trace_id = SecureRandom.uuid

    trace1 = AgentLightningTrace.create!(
      entity: @entity,
      user: @user,
      trace_id: trace_id,
      trace_type: "workflow",
      status: "completed",
      input_data: { request: "first" },
      output_data: {}
    )

    # Attempt to create duplicate
    duplicate_attempt = AgentLightningTrace.new(
      entity: @entity,
      user: @user,
      trace_id: trace_id,
      trace_type: "workflow",
      status: "completed",
      input_data: { request: "second" },
      output_data: {}
    )

    assert_not duplicate_attempt.save
    assert_equal 1, AgentLightningTrace.where(trace_id: trace_id).count
  end

  test "handles training job failure and recovery" do
    training_service = AgentLightningTrainingService.new(@entity)

    # Create traces
    2.times do
      lightning_store = LightningStoreService.new(@entity, @user)
      trace = lightning_store.start_workflow_trace(
        @workflow_execution,
        @task_session,
        "test"
      )
      lightning_store.record_llm_call(
        model: "claude-sonnet-4-5",
        agent_role: "executor",
        system_prompt: {},
        user_messages: [],
        response_content: {},
        input_tokens: 100,
        output_tokens: 50,
        latency_ms: 1000
      )
      lightning_store.record_reward(reward_type: "completion", reward_value: 0.8, source: "automated")
      lightning_store.complete_trace(output_data: { result: "success" })
    end

    # First training attempt
    result1 = training_service.execute_training

    assert result1[:success]

    # Second training attempt should handle already-trained traces
    new_lightning_store = LightningStoreService.new(@entity, @user)
    trace = new_lightning_store.start_workflow_trace(
      @workflow_execution,
      @task_session,
      "new test"
    )
    new_lightning_store.record_llm_call(
      model: "claude-sonnet-4-5",
      agent_role: "executor",
      system_prompt: {},
      user_messages: [],
      response_content: {},
      input_tokens: 100,
      output_tokens: 50,
      latency_ms: 1000
    )
    new_lightning_store.record_reward(reward_type: "completion", reward_value: 0.85, source: "automated")
    new_lightning_store.complete_trace(output_data: { result: "success" })

    # Only new trace should be available for next training
    available = training_service.get_training_traces
    assert_equal 1, available.count
  end

  test "handles phase execution with multiple retries" do
    lightning_store = LightningStoreService.new(@entity, @user)
    trace = lightning_store.start_workflow_trace(
      @workflow_execution,
      @task_session,
      "test"
    )

    # Simulate phase with retries
    phase = lightning_store.record_phase_execution(
      phase_id: "execute_goal",
      phase_type: "execute_goal",
      workflow_execution: @workflow_execution,
      phase_input: { goal: "test" },
      status: "running",
      attempts: 1
    )

    # Simulate retry
    lightning_store.update_phase_execution(
      phase,
      status: "running",
      attempts: 2
    )

    # Final success
    lightning_store.update_phase_execution(
      phase,
      status: "success",
      attempts: 3,
      met_success_criteria: true,
      phase_success_score: 0.8
    )

    phase.reload
    assert_equal 3, phase.attempts
    assert_equal 2, phase.retry_count
    assert phase.successful?
  end
end
