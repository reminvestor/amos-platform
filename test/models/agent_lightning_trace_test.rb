require "test_helper"

class AgentLightningTraceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @workflow_execution = workflow_executions(:one)
    @task_session = task_sessions(:one)
  end

  test "should create trace with valid attributes" do
    trace = AgentLightningTrace.new(
      entity: @entity,
      user: @user,
      workflow_execution: @workflow_execution,
      task_session: @task_session,
      trace_id: SecureRandom.uuid,
      trace_type: "workflow",
      status: "pending",
      input_data: { request_text: "Create a landing page" },
      output_data: {}
    )

    assert trace.save, trace.errors.full_messages.join(", ")
  end

  test "should validate presence of trace_id" do
    trace = AgentLightningTrace.new(
      entity: @entity,
      user: @user,
      trace_type: "workflow",
      status: "pending"
    )

    assert_not trace.save
    assert trace.errors[:trace_id].present?
  end

  test "should validate uniqueness of trace_id" do
    trace_id = SecureRandom.uuid
    AgentLightningTrace.create!(
      entity: @entity,
      user: @user,
      trace_id: trace_id,
      trace_type: "workflow",
      status: "pending",
      input_data: {},
      output_data: {}
    )

    duplicate = AgentLightningTrace.new(
      entity: @entity,
      user: @user,
      trace_id: trace_id,
      trace_type: "workflow",
      status: "pending",
      input_data: {},
      output_data: {}
    )

    assert_not duplicate.save
    assert duplicate.errors[:trace_id].present?
  end

  test "should validate trace_type inclusion" do
    trace = AgentLightningTrace.new(
      entity: @entity,
      user: @user,
      trace_id: SecureRandom.uuid,
      trace_type: "invalid_type",
      status: "pending"
    )

    assert_not trace.save
    assert trace.errors[:trace_type].present?
  end

  test "should validate status inclusion" do
    trace = AgentLightningTrace.new(
      entity: @entity,
      user: @user,
      trace_id: SecureRandom.uuid,
      trace_type: "workflow",
      status: "invalid_status"
    )

    assert_not trace.save
    assert trace.errors[:status].present?
  end

  test "should calculate success_rate" do
    trace = AgentLightningTrace.create!(
      entity: @entity,
      user: @user,
      trace_id: SecureRandom.uuid,
      trace_type: "workflow",
      status: "completed",
      input_data: {},
      output_data: {},
      intermediate_steps: [
        { status: "success" },
        { status: "success" },
        { status: "failed" }
      ]
    )

    assert_equal 66.67, trace.success_rate
  end

  test "should calculate total_cost" do
    trace = AgentLightningTrace.create!(
      entity: @entity,
      user: @user,
      trace_id: SecureRandom.uuid,
      trace_type: "workflow",
      status: "completed",
      input_data: {},
      output_data: {},
      cost_estimate: 0.05
    )

    assert_equal 0.05, trace.total_cost
  end

  test "should calculate total_reward from agent_rewards" do
    trace = AgentLightningTrace.create!(
      entity: @entity,
      user: @user,
      trace_id: SecureRandom.uuid,
      trace_type: "workflow",
      status: "completed",
      input_data: {},
      output_data: {}
    )

    AgentReward.create!(
      entity: @entity,
      agent_lightning_trace: trace,
      reward_type: "completion",
      reward_value: 0.5,
      source: "automated",
      assigned_at: Time.current
    )

    AgentReward.create!(
      entity: @entity,
      agent_lightning_trace: trace,
      reward_type: "quality",
      reward_value: 0.3,
      source: "automated",
      assigned_at: Time.current
    )

    assert_equal 0.8, trace.total_reward
  end

  test "should mark trace as training_ready" do
    trace = AgentLightningTrace.create!(
      entity: @entity,
      user: @user,
      trace_id: SecureRandom.uuid,
      trace_type: "workflow",
      status: "pending",
      input_data: {},
      output_data: {}
    )

    trace.mark_training_ready

    assert trace.included_in_training
    assert_equal "training_ready", trace.status
  end

  test "should generate training_summary" do
    trace = AgentLightningTrace.create!(
      entity: @entity,
      user: @user,
      trace_id: SecureRandom.uuid,
      trace_type: "workflow",
      status: "completed",
      input_data: { request: "test" },
      output_data: { result: "success" },
      token_count: 1500,
      duration_ms: 2000,
      reward_signal: 0.85,
      intermediate_steps: [
        { status: "success" },
        { status: "success" }
      ]
    )

    summary = trace.training_summary

    assert_equal trace.trace_id, summary[:trace_id]
    assert_equal "workflow", summary[:type]
    assert_equal 1500, summary[:token_count]
    assert_equal 2000, summary[:duration_ms]
    assert_equal 0.85, summary[:reward]
    assert_equal 100.0, summary[:success_rate]
  end

  test "should have many associations" do
    trace = AgentLightningTrace.create!(
      entity: @entity,
      user: @user,
      trace_id: SecureRandom.uuid,
      trace_type: "workflow",
      status: "completed",
      input_data: {},
      output_data: {}
    )

    llm_call = AgentLLMCall.create!(
      entity: @entity,
      agent_lightning_trace: trace,
      call_id: SecureRandom.uuid,
      model: "claude-sonnet-4-5",
      agent_role: "executor",
      system_prompt: {},
      user_messages: [],
      response_content: {},
      input_tokens: 100,
      output_tokens: 50,
      total_tokens: 150,
      latency_ms: 1000,
      status: "success",
      called_at: Time.current
    )

    assert_includes trace.agent_llm_calls, llm_call
  end
end
