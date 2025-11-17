require "test_helper"

class AgentLightningWorkflowTest < ActionDispatch::IntegrationTest
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @workflow_execution = workflow_executions(:one)
    @task_session = task_sessions(:one)

    # Ensure entity has Agent Lightning configured
    @entity.create_agent_lightning_config!(
      enabled: true,
      mode: "optimizing",
      training_strategy: "prompt_optimization",
      min_traces_for_training: 2
    ) unless @entity.agent_lightning_config
  end

  test "complete agent lightning workflow from message to training" do
    # Step 1: Start trace collection
    lightning_store = LightningStoreService.new(@entity, @user)
    trace = lightning_store.start_workflow_trace(
      @workflow_execution,
      @task_session,
      "Create a landing page for my SaaS"
    )

    assert trace.persisted?
    assert_equal "pending", trace.status

    # Step 2: Record LLM call (simulating Bedrock call)
    llm_call = lightning_store.record_llm_call(
      model: "claude-sonnet-4-5",
      agent_role: "planner",
      system_prompt: {
        instructions: "You are a helpful planning agent",
        available_templates: ["landing_page_v2"]
      },
      user_messages: [
        { role: "user", content: "Create a landing page for my SaaS" }
      ],
      response_content: {
        template_to_use: "landing_page_creation_v2",
        reasoning: "User wants a landing page, matching template available"
      },
      input_tokens: 500,
      output_tokens: 150,
      latency_ms: 1200,
      status: "success",
      parsed_actions: [
        { tool: "use_template", args: { template: "landing_page_creation_v2" } }
      ],
      success_score: 0.95
    )

    assert llm_call.persisted?
    assert_equal "planner", llm_call.agent_role
    assert_equal 650, llm_call.total_tokens

    # Step 3: Record tool execution
    tool_execution = lightning_store.record_tool_execution(
      tool_name: "generate_ai_landing_page",
      tool_category: "content_generation",
      input_arguments: {
        title: "My SaaS App",
        description: "The best SaaS solution"
      },
      output_result: {
        page_id: "landing_123",
        url: "https://example.com/landing",
        success: true
      },
      status: "success",
      execution_time_ms: 8000
    )

    assert tool_execution.persisted?
    assert_equal "landing_123", tool_execution.output_result["page_id"]

    # Step 4: Record phase execution
    phase_execution = lightning_store.record_phase_execution(
      phase_id: "execute_goal",
      phase_type: "execute_goal",
      workflow_execution: @workflow_execution,
      phase_input: { goal: "Generate landing page" },
      status: "success",
      duration_ms: 8500,
      phase_output: { page_id: "landing_123" },
      success_criteria_met: true
    )

    assert phase_execution.persisted?
    assert phase_execution.met_success_criteria

    # Step 5: Add intermediate steps
    lightning_store.add_step(step_description: "Planning workflow", status: "success")
    lightning_store.add_step(step_description: "Executing tools", status: "success")
    lightning_store.add_step(step_description: "Validating output", status: "success")

    # Step 6: Complete trace with output
    lightning_store.complete_trace(
      output_data: {
        result: "success",
        landing_page_id: "landing_123",
        landing_page_url: "https://example.com/landing"
      },
      duration_ms: 10000,
      status: "completed"
    )

    trace.reload
    assert_equal "completed", trace.status
    assert_equal 10000, trace.duration_ms
    assert_equal 3, trace.intermediate_steps.count

    # Step 7: Record user satisfaction reward
    reward = lightning_store.record_reward(
      reward_type: "completion",
      reward_value: 0.95,
      source: "automated",
      reason: "Landing page created successfully with high quality"
    )

    assert reward.persisted?
    trace.reload
    assert_equal 0.95, trace.reward_signal

    # Step 8: Create another successful trace for training
    lightning_store2 = LightningStoreService.new(@entity, @user)
    trace2 = lightning_store2.start_workflow_trace(
      @workflow_execution,
      @task_session,
      "Create an email campaign"
    )

    lightning_store2.record_llm_call(
      model: "claude-sonnet-4-5",
      agent_role: "executor",
      system_prompt: { instructions: "Execute email campaign creation" },
      user_messages: [{ role: "user", content: "Create email campaign" }],
      response_content: {},
      input_tokens: 400,
      output_tokens: 100,
      latency_ms: 1000,
      status: "success"
    )

    lightning_store2.record_tool_execution(
      tool_name: "create_object",
      tool_category: "crud",
      input_arguments: { object_type: "campaigns", data: { name: "Test Campaign" } },
      output_result: { id: "campaign_456", created: true },
      status: "success",
      execution_time_ms: 500
    )

    lightning_store2.complete_trace(
      output_data: { result: "success", campaign_id: "campaign_456" },
      duration_ms: 2000
    )

    lightning_store2.record_reward(
      reward_type: "completion",
      reward_value: 0.88,
      source: "automated"
    )

    # Step 9: Verify traces are ready for training
    traces = @entity.agent_lightning_traces.with_reward.count
    assert_equal 2, traces

    # Step 10: Execute training
    training_service = AgentLightningTrainingService.new(@entity)
    assert training_service.config.ready_for_training?

    training_result = training_service.execute_training

    assert training_result[:success]
    assert training_result[:job_id].present?
    assert training_result[:traces_used] > 0
    assert training_result[:improvement].is_a?(Numeric)

    # Step 11: Verify training job was created
    job = AgentTrainingJob.find_by(job_id: training_result[:job_id])
    assert job
    assert_equal "completed", job.status
    assert_equal "prompt_optimization", job.job_type
    assert job.improvement_score.present?

    # Step 12: Verify traces marked as included in training
    trace.reload
    trace2.reload
    assert trace.included_in_training
    assert trace2.included_in_training
  end

  test "workflow handles failed tool execution" do
    lightning_store = LightningStoreService.new(@entity, @user)
    trace = lightning_store.start_workflow_trace(
      @workflow_execution,
      @task_session,
      "Create campaign"
    )

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

    # Record failed tool execution
    lightning_store.record_tool_execution(
      tool_name: "create_object",
      tool_category: "crud",
      input_arguments: { object_type: "campaigns", data: {} },
      output_result: { error: "Missing required fields" },
      status: "error",
      execution_time_ms: 200,
      error_message: "Validation failed: name is required"
    )

    lightning_store.complete_trace(
      output_data: { result: "failed", error: "Tool execution failed" },
      status: "failed"
    )

    # Record failure reward
    lightning_store.record_reward(
      reward_type: "completion",
      reward_value: 0.2,
      source: "automated",
      reason: "Tool execution failed due to validation"
    )

    trace.reload
    assert_equal "failed", trace.status
    assert_equal 0.2, trace.reward_signal
  end

  test "workflow tracks token costs and efficiency" do
    lightning_store = LightningStoreService.new(@entity, @user)
    trace = lightning_store.start_workflow_trace(
      @workflow_execution,
      @task_session,
      "test"
    )

    # First LLM call
    lightning_store.record_llm_call(
      model: "claude-sonnet-4-5",
      agent_role: "executor",
      system_prompt: {},
      user_messages: [],
      response_content: {},
      input_tokens: 1000,
      output_tokens: 500,
      latency_ms: 1500
    )

    # Second LLM call
    lightning_store.record_llm_call(
      model: "claude-sonnet-4-5",
      agent_role: "executor",
      system_prompt: {},
      user_messages: [],
      response_content: {},
      input_tokens: 800,
      output_tokens: 400,
      latency_ms: 1200
    )

    lightning_store.complete_trace(
      output_data: { result: "success" },
      duration_ms: 3000
    )

    trace.reload

    # Verify token tracking
    assert_equal 2700, trace.token_count  # 1000 + 500 + 800 + 400
    assert trace.cost_estimate > 0

    # Verify we can retrieve all LLM calls
    assert_equal 2, trace.agent_llm_calls.count
    total_tokens = trace.agent_llm_calls.sum(:total_tokens)
    assert_equal 2700, total_tokens
  end

  test "workflow generates training summary" do
    lightning_store = LightningStoreService.new(@entity, @user)
    trace = lightning_store.start_workflow_trace(
      @workflow_execution,
      @task_session,
      "Create landing page"
    )

    lightning_store.record_llm_call(
      model: "claude-sonnet-4-5",
      agent_role: "planner",
      system_prompt: { instructions: "Plan workflow" },
      user_messages: [{ role: "user", content: "Create landing page" }],
      response_content: { plan: "Multi-step plan" },
      input_tokens: 500,
      output_tokens: 200,
      latency_ms: 1000
    )

    lightning_store.add_step(step_description: "Step 1", status: "success")
    lightning_store.add_step(step_description: "Step 2", status: "success")

    lightning_store.complete_trace(
      output_data: { result: "success" },
      duration_ms: 2000
    )

    lightning_store.record_reward(reward_type: "completion", reward_value: 0.9, source: "automated")

    trace.reload
    summary = trace.training_summary

    assert_equal trace.trace_id, summary[:trace_id]
    assert_equal "workflow", summary[:type]
    assert_equal 700, summary[:token_count]
    assert_equal 2000, summary[:duration_ms]
    assert_equal 0.9, summary[:reward]
    assert_equal 100.0, summary[:success_rate]
  end
end
