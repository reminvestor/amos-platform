# frozen_string_literal: true

require "test_helper"

class V3::ToolRegistryTest < ActiveSupport::TestCase
  # ══════════════════════════════════════════════════════════════
  # LLM TOOL SET (single-model architecture)
  # ══════════════════════════════════════════════════════════════

  test "LLM_TOOLS contains the correct tool set" do
    expected = %w[
      platform_create platform_update platform_query platform_execute
      web_search view_web_page read_file bash browser_use load_canvas
    ]
    assert_equal expected.sort, V3::ToolRegistry::LLM_TOOLS.keys.sort
  end

  test "LLM_TOOLS contains 10 tools" do
    assert_equal 10, V3::ToolRegistry::LLM_TOOLS.keys.length
  end

  test "platform tools are LLM-facing (single-model architecture)" do
    %w[platform_create platform_update platform_query platform_execute].each do |tool|
      assert V3::ToolRegistry::LLM_TOOLS.key?(tool), "#{tool} should be in LLM_TOOLS"
    end
  end

  test "INTERNAL_TOOLS preserves backward compat tools" do
    internal = V3::ToolRegistry::INTERNAL_TOOLS
    assert internal.key?("platform_do"), "Should keep platform_do for backward compat"
    assert internal.key?("discover"), "Should keep discover internally"
  end

  test "ALL_TOOLS includes both LLM and internal tools" do
    all = V3::ToolRegistry::ALL_TOOLS
    assert all.key?("platform_create"), "Should have platform_create"
    assert all.key?("platform_query"), "Should have platform_query"
    assert all.key?("bash"), "Should have bash"
    assert all.key?("platform_do"), "Should have platform_do (backward compat)"
  end

  # ══════════════════════════════════════════════════════════════
  # BEDROCK TOOLS (what the LLM sees)
  # ══════════════════════════════════════════════════════════════

  test "get_bedrock_tools returns LLM-facing tools" do
    tools = V3::ToolRegistry.get_bedrock_tools
    tool_names = tools.map { |t| t[:name] }

    # Should include all platform tools (single-model architecture)
    assert_includes tool_names, "platform_create"
    assert_includes tool_names, "platform_update"
    assert_includes tool_names, "platform_query"
    assert_includes tool_names, "platform_execute"
    assert_includes tool_names, "web_search"
    assert_includes tool_names, "bash"
    assert_includes tool_names, "load_canvas"

    # Should NOT include internal tools
    refute_includes tool_names, "platform_do"
    refute_includes tool_names, "discover"
  end

  # ══════════════════════════════════════════════════════════════
  # TOOL EXECUTION (both LLM and internal)
  # ══════════════════════════════════════════════════════════════

  test "can execute LLM tools" do
    assert V3::ToolRegistry.tool_exists?("platform_create")
    assert V3::ToolRegistry.tool_exists?("platform_query")
    assert V3::ToolRegistry.tool_exists?("bash")
  end

  test "can execute internal tools" do
    assert V3::ToolRegistry.tool_exists?("platform_do")
    assert V3::ToolRegistry.tool_exists?("discover")
  end

  test "tool_names returns LLM-facing names" do
    names = V3::ToolRegistry.tool_names
    assert_includes names, "platform_create"
    assert_includes names, "platform_query"
    assert_includes names, "load_canvas"
    refute_includes names, "platform_do"
    refute_includes names, "discover"
  end

  test "all_tool_names returns everything" do
    names = V3::ToolRegistry.all_tool_names
    assert_includes names, "platform_create"
    assert_includes names, "platform_do"
    assert_includes names, "discover"
  end

  # ══════════════════════════════════════════════════════════════
  # BACKWARD COMPATIBILITY
  # ══════════════════════════════════════════════════════════════

  test "POWER_TOOLS alias still works" do
    assert_equal V3::ToolRegistry::ALL_TOOLS, V3::ToolRegistry::POWER_TOOLS
  end
end
