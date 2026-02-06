# frozen_string_literal: true

require "test_helper"

class V3::AgentLoopTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @entity = entities(:one)
    @session_id = SecureRandom.uuid
  end

  test "initializes with correct defaults" do
    agent = V3::AgentLoop.new(
      user: @user,
      entity: @entity,
      session_id: @session_id
    )

    assert_equal @user, agent.user
    assert_equal @entity, agent.entity
    assert_equal @session_id, agent.session_id
    assert agent.model.present?
  end

  test "accepts custom model" do
    agent = V3::AgentLoop.new(
      user: @user,
      entity: @entity,
      session_id: @session_id,
      model: "claude-3-haiku"
    )

    assert_equal "claude-3-haiku", agent.model
  end

  test "MAX_TOOL_TURNS is reasonable" do
    assert_equal 25, V3::AgentLoop::MAX_TOOL_TURNS
  end

  test "MAX_REPEATED_FAILURES is reasonable" do
    assert_equal 3, V3::AgentLoop::MAX_REPEATED_FAILURES
  end
end
