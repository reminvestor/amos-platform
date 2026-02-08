# frozen_string_literal: true

require "test_helper"

class V3::ToolRegistryTest < ActiveSupport::TestCase
  # ══════════════════════════════════════════════════════════════
  # LLM TOOL SET
  # ══════════════════════════════════════════════════════════════

  test "LLM_TOOLS contains exactly 9 tools" do
    assert_equal 9, V3::ToolRegistry::LLM_TOOLS.keys.length
  end

  test "LLM_TOOLS has the correct tool set" do
    expected = %w[platform_do platform_query web_search view_web_page read_file bash browser_use ask_user load_canvas]
    assert_equal expected.sort, V3::ToolRegistry::LLM_TOOLS.keys.sort
  end

  test "INTERNAL_TOOLS preserves old CRUD tools" do
    internal = V3::ToolRegistry::INTERNAL_TOOLS
    assert internal.key?("platform_create"), "Should keep platform_create internally"
    assert internal.key?("platform_update"), "Should keep platform_update internally"
    assert internal.key?("platform_execute"), "Should keep platform_execute internally"
  end

  test "ALL_TOOLS includes both LLM and internal tools" do
    all = V3::ToolRegistry::ALL_TOOLS
    assert all.key?("platform_do"), "Should have platform_do"
    assert all.key?("platform_create"), "Should have platform_create"
    assert all.key?("platform_query"), "Should have platform_query"
    assert all.key?("bash"), "Should have bash"
  end

  # ══════════════════════════════════════════════════════════════
  # BEDROCK TOOLS (what the LLM sees)
  # ══════════════════════════════════════════════════════════════

  test "get_bedrock_tools returns only LLM-facing tools" do
    tools = V3::ToolRegistry.get_bedrock_tools
    tool_names = tools.map { |t| t[:name] }

    # Should include LLM tools
    assert_includes tool_names, "platform_do"
    assert_includes tool_names, "platform_query"
    assert_includes tool_names, "web_search"
    assert_includes tool_names, "bash"
    assert_includes tool_names, "ask_user"
    assert_includes tool_names, "load_canvas"

    # Should NOT include internal tools
    refute_includes tool_names, "platform_create"
    refute_includes tool_names, "platform_update"
    refute_includes tool_names, "platform_execute"
    refute_includes tool_names, "discover"
    refute_includes tool_names, "read_file"
  end

  # ══════════════════════════════════════════════════════════════
  # TOOL EXECUTION (both LLM and internal)
  # ══════════════════════════════════════════════════════════════

  test "can execute LLM tools" do
    assert V3::ToolRegistry.tool_exists?("platform_do")
    assert V3::ToolRegistry.tool_exists?("bash")
  end

  test "can execute internal tools" do
    assert V3::ToolRegistry.tool_exists?("platform_create")
    assert V3::ToolRegistry.tool_exists?("platform_update")
    assert V3::ToolRegistry.tool_exists?("platform_execute")
  end

  test "tool_names returns only LLM-facing names" do
    names = V3::ToolRegistry.tool_names
    assert_includes names, "platform_do"
    assert_includes names, "load_canvas"
    refute_includes names, "platform_create"
    refute_includes names, "platform_execute"
  end

  test "all_tool_names returns everything" do
    names = V3::ToolRegistry.all_tool_names
    assert_includes names, "platform_do"
    assert_includes names, "platform_create"
    assert_includes names, "platform_update"
    assert_includes names, "platform_execute"
  end

  # ══════════════════════════════════════════════════════════════
  # BACKWARD COMPATIBILITY
  # ══════════════════════════════════════════════════════════════

  test "POWER_TOOLS alias still works" do
    assert_equal V3::ToolRegistry::ALL_TOOLS, V3::ToolRegistry::POWER_TOOLS
  end
end
