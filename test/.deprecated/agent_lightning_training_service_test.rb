require "test_helper"

class AgentLightningTrainingServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @service = AgentLightningTrainingService.new(@entity)

    # Create default config if needed
    @entity.create_agent_lightning_config!(
      enabled: true,
      mode: "optimizing",
      training_strategy: "prompt_optimization",
      min_traces_for_training: 2
    ) unless @entity.agent_lightning_config
  end

  test "should initialize service with entity" do
    assert_equal @entity, @service.entity
    assert @service.config
  end

  test "should get training traces" do
    # Create traces with rewards
    trace1 = create_trace_with_reward(0.8)
    trace2 = create_trace_with_reward(0.9)
    trace3 = create_trace_with_reward(0.3)

    traces = @service.get_training_traces

    assert traces.any?
    assert traces.map(&:id).include?(trace1.id)
  end

  test "should not run training if disabled" do
    @service.config.update!(enabled: false)

    result = @service.run_training_if_ready

    assert_not result
  end

  test "should not run training if insufficient traces" do
    @service.config.update!(min_traces_for_training: 100)

    result = @service.run_training_if_ready

    assert_not result
  end

  test "should analyze training data" do
    lightning_store = LightningStoreService.new(@entity, @user)

    3.times do
      trace = lightning_store.start_workflow_trace(
        workflow_executions(:one),
        task_sessions(:one),
        "test"
      )
      lightning_store.record_llm_call(
        model: "claude-sonnet-4-5",
        agent_role: "executor",
        system_prompt: {},
        user_messages: [],
        response_content: {},
        input_tokens: 1000,
        output_tokens: 500,
        latency_ms: 2000
      )
      lightning_store.record_reward(reward_type: "completion", reward_value: 0.8, source: "automated")
      lightning_store.complete_trace(
        output_data: { result: "success" },
        duration_ms: 2500
      )
    end

    training_data = @service.get_training_traces.map(&:training_summary)
    metrics = @service.analyze_training_data(training_data)

    assert metrics.key?(:total_traces)
    assert metrics.key?(:avg_tokens_per_trace)
    assert metrics.key?(:success_rate)
    assert metrics.key?(:avg_reward)
  end

  test "should create training job" do
    traces = []
    2.times do
      traces << create_trace_with_reward(0.85)
    end

    job = @service.send(:create_training_job, traces)

    assert job.persisted?
    assert_equal @entity, job.entity
    assert_equal "prompt_optimization", job.job_type
    assert_equal "pending", job.status
    assert_equal 2, job.total_traces_available
  end

  test "should execute prompt optimization training" do
    lightning_store = LightningStoreService.new(@entity, @user)

    # Create successful traces
    2.times do
      trace = lightning_store.start_workflow_trace(
        workflow_executions(:one),
        task_sessions(:one),
        "test"
      )
      lightning_store.record_llm_call(
        model: "claude-sonnet-4-5",
        agent_role: "executor",
        system_prompt: { instructions: "Be helpful" },
        user_messages: [],
        response_content: {},
        input_tokens: 100,
        output_tokens: 50,
        latency_ms: 1000
      )
      lightning_store.record_reward(reward_type: "completion", reward_value: 0.9, source: "automated")
      lightning_store.complete_trace(output_data: { result: "success" })
    end

    traces = @service.get_training_traces
    results = @service.send(:optimize_prompts, traces.map(&:training_summary), {})

    assert_equal "prompt_optimization", results[:strategy]
    assert results.key?(:successful_patterns)
    assert results.key?(:failed_patterns)
    assert results.key?(:recommended_changes)
  end

  test "should execute supervised finetuning preparation" do
    lightning_store = LightningStoreService.new(@entity, @user)

    2.times do
      trace = lightning_store.start_workflow_trace(
        workflow_executions(:one),
        task_sessions(:one),
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
      lightning_store.complete_trace(output_data: { result: "success" }, duration_ms: 1500)
    end

    @service.config.update!(training_strategy: "supervised_finetuning")

    training_data = @service.get_training_traces.map(&:training_summary)
    results = @service.send(:prepare_finetuning_data, training_data, {})

    assert_equal "supervised_finetuning", results[:strategy]
    assert results.key?(:dataset_size)
    assert results.key?(:dataset)
  end

  test "should execute rl training" do
    lightning_store = LightningStoreService.new(@entity, @user)

    2.times do
      trace = lightning_store.start_workflow_trace(
        workflow_executions(:one),
        task_sessions(:one),
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
      lightning_store.record_reward(reward_type: "completion", reward_value: 0.75, source: "automated")
      lightning_store.complete_trace(output_data: { result: "success" })
    end

    @service.config.update!(training_strategy: "rl_training")

    training_data = @service.get_training_traces.map(&:training_summary)
    results = @service.send(:execute_rl_training, training_data, {})

    assert_equal "rl_training", results[:strategy]
    assert_equal "hierarchical_rl", results[:algorithm]
    assert results.key?(:workflow_improvements)
  end

  test "should calculate improvement percentage" do
    lightning_store = LightningStoreService.new(@entity, @user)

    3.times do
      trace = lightning_store.start_workflow_trace(
        workflow_executions(:one),
        task_sessions(:one),
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
      lightning_store.record_reward(reward_type: "completion", reward_value: 0.85, source: "automated")
      lightning_store.complete_trace(output_data: { result: "success" })
    end

    traces = @service.get_training_traces
    result = @service.execute_training(traces)

    assert result[:success]
    assert result.key?(:improvement)
    assert result[:improvement].is_a?(Numeric)
  end

  test "should mark traces as training ready after training" do
    trace = create_trace_with_reward(0.8)

    assert_not trace.included_in_training

    traces = [@trace]
    @service.execute_training(traces)

    trace.reload
    assert trace.included_in_training
  end

  test "should create training job record" do
    trace = create_trace_with_reward(0.85)

    result = @service.execute_training([@trace])

    assert result[:success]
    assert result.key?(:job_id)

    job = AgentTrainingJob.find_by(job_id: result[:job_id])
    assert job.persisted?
    assert_equal "completed", job.status
  end

  test "should handle training errors gracefully" do
    # Create invalid state to trigger error
    @service.config.update!(min_traces_for_training: 1000)

    result = @service.execute_training([])

    assert_not result[:success]
    assert result.key?(:error)
  end

  private

  def create_trace_with_reward(reward_value)
    lightning_store = LightningStoreService.new(@entity, @user)
    trace = lightning_store.start_workflow_trace(
      workflow_executions(:one),
      task_sessions(:one),
      "test request"
    )
    lightning_store.record_llm_call(
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
    lightning_store.record_reward(
      reward_type: "completion",
      reward_value: reward_value,
      source: "automated"
    )
    lightning_store.complete_trace(
      output_data: { result: "success" },
      duration_ms: 2000
    )
    trace.reload
  end
end
