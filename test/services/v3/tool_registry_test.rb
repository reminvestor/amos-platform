# frozen_string_literal: true

require "test_helper"

class V3::ToolRegistryTest < ActiveSupport::TestCase
  test "POWER_TOOLS has exactly 10 tools" do
    assert_equal 10, V3::ToolRegistry::POWER_TOOLS.keys.length,
      "V3 should have exactly 10 power tools, got: #{V3::ToolRegistry::POWER_TOOLS.keys}"
  end

  test "all expected power tools are registered" do
    expected = %w[
      platform_query platform_create platform_update platform_execute
      discover read_file web_search bash load_canvas ask_user
    ]

    expected.each do |tool_name|
      assert V3::ToolRegistry::POWER_TOOLS.key?(tool_name),
        "Missing power tool: #{tool_name}"
    end
  end

  test "get_bedrock_tools returns tool definitions" do
    tools = V3::ToolRegistry.get_bedrock_tools

    assert tools.is_a?(Array)
    assert tools.length >= 10, "Should have at least 10 tools (power + memory), got #{tools.length}"

    # Check each tool has required fields
    tools.each do |tool|
      assert tool[:name].present?, "Tool missing name: #{tool.inspect}"
      assert tool[:description].present?, "Tool #{tool[:name]} missing description"
      assert tool[:parameters].present?, "Tool #{tool[:name]} missing parameters"
    end
  end

  test "tool_exists? returns true for registered tools" do
    assert V3::ToolRegistry.tool_exists?("platform_query")
    assert V3::ToolRegistry.tool_exists?("bash")
    assert V3::ToolRegistry.tool_exists?("discover")
    refute V3::ToolRegistry.tool_exists?("nonexistent_tool")
  end

  test "tool_names returns all tool names" do
    names = V3::ToolRegistry.tool_names
    assert names.include?("platform_query")
    assert names.include?("bash")
    assert names.include?("load_canvas")
  end

  test "execute returns error for unknown tool" do
    user = users(:one) rescue nil
    entity = entities(:one) rescue nil

    # Skip if fixtures aren't available
    skip "Fixtures not available" unless user && entity

    result = V3::ToolRegistry.execute("nonexistent", {}, user: user, entity: entity)
    assert_equal false, result[:success]
    assert_match /Unknown/, result[:error]
  end
end
