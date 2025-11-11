require "test_helper"

class Admin::AgentLightningControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin_user = users(:admin)
    sign_in @admin_user
    @entity = entities(:one)
    set_current_entity(@entity)

    @entity.create_agent_lightning_config!(
      enabled: true,
      mode: "optimizing",
      training_strategy: "prompt_optimization",
      min_traces_for_training: 2
    ) unless @entity.agent_lightning_config
  end

  test "dashboard shows configuration status" do
    get admin_agent_lightning_dashboard_path

    assert_response :success
    assert_includes response.body, "Agent Lightning Dashboard"
    assert_includes response.body, "Configuration"
  end

  test "dashboard displays key metrics" do
    lightning_store = LightningStoreService.new(@entity, @admin_user)
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
    lightning_store.complete_trace(output_data: { result: "success" })

    get admin_agent_lightning_dashboard_path

    assert_response :success
    assert_includes response.body, "Success Rate"
    assert_includes response.body, "Avg Tokens"
  end

  test "dashboard shows training readiness" do
    # Create minimum traces
    2.times do
      lightning_store = LightningStoreService.new(@entity, @admin_user)
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
      lightning_store.complete_trace(output_data: { result: "success" })
    end

    get admin_agent_lightning_dashboard_path

    assert_response :success
    assert_includes response.body, "Training Readiness"
  end

  test "train_now triggers training" do
    # Create minimum traces for training
    2.times do
      lightning_store = LightningStoreService.new(@entity, @admin_user)
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
      lightning_store.complete_trace(output_data: { result: "success" })
    end

    post admin_agent_lightning_train_now_path

    assert_redirected_to admin_agent_lightning_dashboard_path
    assert_includes flash[:notice], "Training completed"
  end

  test "metrics action shows detailed metrics" do
    # Create traces
    3.times do
      lightning_store = LightningStoreService.new(@entity, @admin_user)
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

    get admin_agent_lightning_metrics_path

    assert_response :success
    assert_includes response.body, "Overall Statistics"
    assert_includes response.body, "Token & Cost Analysis"
  end

  test "metrics with custom date range" do
    get admin_agent_lightning_metrics_path(days: 7)

    assert_response :success
    assert_includes response.body, "Last 7 days"
  end

  test "training_history shows paginated jobs" do
    # Create training jobs
    2.times do
      job = AgentTrainingJob.create!(
        entity: @entity,
        job_type: "prompt_optimization",
        status: "completed",
        traces_used: 5,
        total_traces_available: 10,
        improvement_score: 15,
        training_results: {},
        completed_at: Time.current
      )
    end

    get admin_agent_lightning_training_history_path

    assert_response :success
    assert_includes response.body, "Training History"
  end

  test "export_data returns JSON export" do
    lightning_store = LightningStoreService.new(@entity, @admin_user)
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
    lightning_store.complete_trace(output_data: { result: "success" })

    get admin_agent_lightning_export_data_path

    assert_response :success
    assert_equal "application/json", response.content_type
  end

  test "non-admin user cannot access dashboard" do
    sign_out @admin_user
    user = users(:one)
    sign_in user

    get admin_agent_lightning_dashboard_path

    assert_redirected_to root_path
  end

  test "dashboard handles empty state gracefully" do
    # Don't create any traces
    get admin_agent_lightning_dashboard_path

    assert_response :success
    assert_includes response.body, "Agent Lightning Dashboard"
  end

  test "dashboard creates default config if missing" do
    @entity.agent_lightning_config.destroy

    get admin_agent_lightning_dashboard_path

    assert_response :success
    assert @entity.reload.agent_lightning_config.present?
  end

  test "LLM call analysis displays by role" do
    lightning_store = LightningStoreService.new(@entity, @admin_user)
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

    get admin_agent_lightning_dashboard_path

    assert_response :success
    assert_includes response.body, "LLM Call Analysis"
  end

  test "tool execution analysis displays top tools" do
    lightning_store = LightningStoreService.new(@entity, @admin_user)
    trace = lightning_store.start_workflow_trace(
      workflow_executions(:one),
      task_sessions(:one),
      "test"
    )
    lightning_store.record_tool_execution(
      tool_name: "generate_landing_page",
      tool_category: "content_generation",
      input_arguments: { title: "Test" },
      output_result: { page_id: "123" },
      status: "success",
      execution_time_ms: 5000
    )
    lightning_store.complete_trace(output_data: { result: "success" })

    get admin_agent_lightning_dashboard_path

    assert_response :success
    assert_includes response.body, "Top Tools"
  end
end
