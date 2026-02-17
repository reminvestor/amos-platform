# frozen_string_literal: true

require "test_helper"

class AgentToolTest < ActiveSupport::TestCase
  fixtures :entities, :agent_plugins

  setup do
    @entity = entities(:one)
    @agent = agent_plugins(:one)
  end

  # ═══════════════════════════════════════════════════════════════
  # BASIC VALIDATIONS
  # ═══════════════════════════════════════════════════════════════

  test "valid agent tool with existing catalog tool" do
    agent_tool = AgentTool.new(
      agent_plugin: @agent,
      tool_name: "ask_user"
    )
    assert agent_tool.valid?, "Should be valid with a tool that exists in catalog: #{agent_tool.errors.full_messages.join(', ')}"
  end

  test "requires tool_name" do
    agent_tool = AgentTool.new(
      agent_plugin: @agent,
      tool_name: nil
    )
    assert_not agent_tool.valid?
    assert_includes agent_tool.errors[:tool_name], "can't be blank"
  end

  test "requires agent_plugin" do
    agent_tool = AgentTool.new(
      agent_plugin: nil,
      tool_name: "ask_user"
    )
    assert_not agent_tool.valid?
  end

  # ═══════════════════════════════════════════════════════════════
  # TOOL EXISTENCE VALIDATION (NOW A WARNING)
  # ═══════════════════════════════════════════════════════════════

  test "allows tools not in ToolCatalog (warning only)" do
    agent_tool = AgentTool.new(
      agent_plugin: @agent,
      tool_name: "nonexistent_custom_tool"
    )

    # Should be valid — validation is now a warning, not a hard error
    assert agent_tool.valid?,
      "AgentTool should not hard-fail on unknown tools, errors: #{agent_tool.errors.full_messages.join(', ')}"
  end

  test "deprecated get_data tool does not block creation" do
    agent_tool = AgentTool.new(
      agent_plugin: @agent,
      tool_name: "get_data"
    )

    assert agent_tool.valid?,
      "Deprecated 'get_data' should not block AgentTool creation"
  end

  test "deprecated get_schema tool does not block creation" do
    agent_tool = AgentTool.new(
      agent_plugin: @agent,
      tool_name: "get_schema"
    )

    assert agent_tool.valid?,
      "Deprecated 'get_schema' should not block AgentTool creation"
  end

  test "can create and save agent tool with unknown tool name" do
    agent_tool = AgentTool.create(
      agent_plugin: @agent,
      tool_name: "dynamic_entity_tool_#{SecureRandom.hex(4)}"
    )

    assert agent_tool.persisted?,
      "Should be able to persist AgentTool with dynamic/unknown tool name"
  end

  # ═══════════════════════════════════════════════════════════════
  # UNIQUENESS
  # ═══════════════════════════════════════════════════════════════

  test "enforces uniqueness scoped to agent_plugin" do
    AgentTool.create!(
      agent_plugin: @agent,
      tool_name: "unique_test_tool"
    )

    duplicate = AgentTool.new(
      agent_plugin: @agent,
      tool_name: "unique_test_tool"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:tool_name], "has already been taken"
  end

  test "allows same tool_name for different agents" do
    other_agent = agent_plugins(:two)

    AgentTool.create!(
      agent_plugin: @agent,
      tool_name: "shared_tool_name"
    )

    other_tool = AgentTool.new(
      agent_plugin: other_agent,
      tool_name: "shared_tool_name"
    )

    assert other_tool.valid?,
      "Same tool_name should be allowed on different agents"
  end

  # ═══════════════════════════════════════════════════════════════
  # HELPER METHODS
  # ═══════════════════════════════════════════════════════════════

  test "tool_available? returns true for catalog tools" do
    agent_tool = AgentTool.new(
      agent_plugin: @agent,
      tool_name: "ask_user"
    )
    assert agent_tool.tool_available?
  end

  test "tool_available? returns false for missing tools" do
    agent_tool = AgentTool.new(
      agent_plugin: @agent,
      tool_name: "nonexistent_tool"
    )
    assert_not agent_tool.tool_available?
  end
end
