require "test_helper"

class AgentLlmCallTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
  end

  test "should create llm_call with valid attributes" do
    call = AgentLlmCall.new(
      entity: @entity,

      call_id: SecureRandom.uuid,
      model: "claude-sonnet-4-5",
      agent_role: "executor",
      system_prompt: { instructions: "test" },
      user_messages: [{ role: "user", content: "test" }],
      response_content: { text: "response" },
      input_tokens: 100,
      output_tokens: 50,
      total_tokens: 150,
      latency_ms: 1000,
      status: "success",
      called_at: Time.current
    )

    assert call.save, call.errors.full_messages.join(", ")
  end

  test "should validate presence of call_id" do
    call = AgentLlmCall.new(
      entity: @entity,
      model: "claude-sonnet-4-5",
      agent_role: "executor",
      status: "success",
      called_at: Time.current
    )

    assert_not call.save
    assert call.errors[:call_id].present?
  end

  test "should validate uniqueness of call_id" do
    call_id = SecureRandom.uuid
    AgentLlmCall.create!(
      entity: @entity,

      call_id: call_id,
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

    duplicate = AgentLlmCall.new(
      entity: @entity,
      call_id: call_id,
      model: "claude-sonnet-4-5",
      agent_role: "executor",
      status: "success",
      called_at: Time.current
    )

    assert_not duplicate.save
    assert duplicate.errors[:call_id].present?
  end

  test "should validate agent_role inclusion" do
    call = AgentLlmCall.new(
      entity: @entity,
      call_id: SecureRandom.uuid,
      model: "claude-sonnet-4-5",
      agent_role: "invalid_role",
      status: "success",
      called_at: Time.current
    )

    assert_not call.save
    assert call.errors[:agent_role].present?
  end

  test "should calculate cost_per_token" do
    call = AgentLlmCall.create!(
      entity: @entity,

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
      cost: 0.003,
      status: "success",
      called_at: Time.current
    )

    cost_per_token = call.cost_per_token
    assert_in_delta 0.00002, cost_per_token, 0.0000001
  end

  test "should identify successful calls" do
    successful_call = AgentLlmCall.create!(
      entity: @entity,

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

    assert successful_call.successful?
  end

  test "should identify failed calls" do
    failed_call = AgentLlmCall.create!(
      entity: @entity,

      call_id: SecureRandom.uuid,
      model: "claude-sonnet-4-5",
      agent_role: "executor",
      system_prompt: {},
      user_messages: [],
      response_content: {},
      input_tokens: 0,
      output_tokens: 0,
      total_tokens: 0,
      latency_ms: 1000,
      status: "error",
      error_message: "API Error",
      called_at: Time.current
    )

    assert_not failed_call.successful?
  end

  test "should generate execution_summary" do
    call = AgentLlmCall.create!(
      entity: @entity,

      call_id: SecureRandom.uuid,
      model: "claude-sonnet-4-5",
      agent_role: "planner",
      system_prompt: {},
      user_messages: [],
      response_content: {},
      input_tokens: 200,
      output_tokens: 100,
      total_tokens: 300,
      latency_ms: 1500,
      status: "success",
      cost: 0.005,
      parsed_actions: [{ tool: "test" }],
      success_score: 0.95,
      called_at: Time.current
    )

    summary = call.execution_summary

    assert_equal call.call_id, summary[:call_id]
    assert_equal "claude-sonnet-4-5", summary[:model]
    assert_equal "planner", summary[:role]
    assert_equal 200, summary[:input_tokens]
    assert_equal 100, summary[:output_tokens]
    assert_equal 1500, summary[:latency_ms]
    assert_equal 1, summary[:actions_count]
    assert_equal 0.95, summary[:success_score]
  end

  test "should filter by status scope" do
    AgentLlmCall.create!(
      entity: @entity,
      call_id: SecureRandom.uuid,
      model: "claude-sonnet-4-5",
      agent_role: "executor",
      status: "success",
      called_at: Time.current
    )

    AgentLlmCall.create!(
      entity: @entity,
      call_id: SecureRandom.uuid,
      model: "claude-sonnet-4-5",
      agent_role: "executor",
      status: "error",
      called_at: Time.current
    )

    assert_equal 1, AgentLlmCall.successful.count
  end
end
