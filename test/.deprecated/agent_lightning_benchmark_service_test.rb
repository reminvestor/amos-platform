require "test_helper"

class AgentLightningBenchmarkServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @service = AgentLightningBenchmarkService.new(@entity)

    @entity.create_agent_lightning_config!(
      enabled: true,
      mode: "optimizing",
      training_strategy: "prompt_optimization"
    ) unless @entity.agent_lightning_config
  end

  test "should generate benchmark report with before and after data" do
    # Create some baseline traces
    2.times do
      lightning_store = LightningStoreService.new(@entity, @user)
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
      lightning_store.complete_trace(output_data: { result: "success" }, duration_ms: 2000)
    end

    report = @service.generate_report

    assert report.is_a?(Hash)
    assert report.key?(:generated_at)
    assert report.key?(:entity_id)
    assert report.key?(:benchmarks)
  end

  test "should benchmark success rate improvement" do
    # Create traces with varying rewards
    rewards = [0.6, 0.7, 0.8, 0.9]
    rewards.each do |reward|
      lightning_store = LightningStoreService.new(@entity, @user)
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
      lightning_store.record_reward(reward_type: "completion", reward_value: reward, source: "automated")
      lightning_store.complete_trace(output_data: { result: "success" })
    end

    report = @service.benchmark_success_rate

    assert report.is_a?(Hash)
    assert report.key?(:success_rate)
    assert report[:success_rate].is_a?(Numeric)
  end

  test "should benchmark cost metrics" do
    5.times do
      lightning_store = LightningStoreService.new(@entity, @user)
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
      lightning_store.complete_trace(output_data: { result: "success" })
    end

    report = @service.benchmark_costs

    assert report.is_a?(Hash)
    assert report.key?(:total_cost)
    assert report.key?(:avg_cost_per_trace)
  end

  test "should benchmark performance metrics" do
    3.times do
      lightning_store = LightningStoreService.new(@entity, @user)
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
        latency_ms: 1500
      )
      lightning_store.complete_trace(output_data: { result: "success" }, duration_ms: 2500)
    end

    report = @service.benchmark_performance

    assert report.is_a?(Hash)
    assert report.key?(:avg_duration_ms)
    assert report.key?(:avg_latency_ms)
  end

  test "should calculate improvements with before and after data" do
    # Create baseline
    3.times do
      lightning_store = LightningStoreService.new(@entity, @user)
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
      lightning_store.record_reward(reward_type: "completion", reward_value: 0.7, source: "automated")
      lightning_store.complete_trace(output_data: { result: "success" }, duration_ms: 2000)
    end

    before_metrics = @service.benchmark_success_rate
    before_cost = @service.benchmark_costs

    improvements = @service.calculate_improvements(
      {
        success_rate: before_metrics[:success_rate],
        total_cost: before_cost[:total_cost],
        avg_duration: 2000
      },
      {
        success_rate: before_metrics[:success_rate] + 0.10,
        total_cost: before_cost[:total_cost] * 0.9,
        avg_duration: 1800
      }
    )

    assert improvements.is_a?(Hash)
    assert improvements.key?(:success_rate_improvement)
    assert improvements.key?(:cost_savings)
    assert improvements.key?(:performance_improvement)
  end

  test "should generate recommendations based on metrics" do
    # Create diverse traces to trigger recommendations
    10.times do
      lightning_store = LightningStoreService.new(@entity, @user)
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
      lightning_store.complete_trace(output_data: { result: "success" }, duration_ms: 2000)
    end

    recommendations = @service.generate_recommendations

    assert recommendations.is_a?(Array)
    assert recommendations.all? { |r| r.is_a?(Hash) }
  end

  test "should benchmark quality metrics" do
    5.times do
      lightning_store = LightningStoreService.new(@entity, @user)
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

    report = @service.benchmark_quality

    assert report.is_a?(Hash)
    assert report.key?(:avg_reward_signal)
  end

  test "should benchmark tool performance" do
    lightning_store = LightningStoreService.new(@entity, @user)
    trace = lightning_store.start_workflow_trace(
      workflow_executions(:one),
      task_sessions(:one),
      "test"
    )

    3.times do |i|
      lightning_store.record_tool_execution(
        tool_name: "generate_landing_page",
        tool_category: "content_generation",
        input_arguments: { title: "Test #{i}" },
        output_result: { page_id: i.to_s },
        status: "success",
        execution_time_ms: 5000
      )
    end

    lightning_store.complete_trace(output_data: { result: "success" })

    report = @service.benchmark_tool_performance

    assert report.is_a?(Hash)
    assert report.key?(:tool_metrics)
  end

  test "should benchmark LLM performance by role" do
    lightning_store = LightningStoreService.new(@entity, @user)
    trace = lightning_store.start_workflow_trace(
      workflow_executions(:one),
      task_sessions(:one),
      "test"
    )

    # Record calls with different roles
    lightning_store.record_llm_call(
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

    lightning_store.record_llm_call(
      model: "claude-sonnet-4-5",
      agent_role: "validator",
      system_prompt: {},
      user_messages: [],
      response_content: {},
      input_tokens: 200,
      output_tokens: 100,
      latency_ms: 1500,
      status: "success"
    )

    lightning_store.complete_trace(output_data: { result: "success" })

    report = @service.benchmark_llm_performance

    assert report.is_a?(Hash)
    assert report.key?(:llm_metrics)
  end

  test "report includes metadata" do
    report = @service.generate_report

    assert report[:entity_id].present?
    assert report[:generated_at].present?
    assert report[:entity_name].present?
  end
end
