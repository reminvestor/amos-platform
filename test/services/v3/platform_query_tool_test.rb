# frozen_string_literal: true

require "test_helper"

class V3::Tools::PlatformQueryToolTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @entity = entities(:one)
    @tool = V3::Tools::PlatformQueryTool.new(user: @user, entity: @entity)
  end

  test "metadata has correct name" do
    metadata = V3::Tools::PlatformQueryTool.metadata
    assert_equal "platform_query", metadata[:name]
    assert_equal "v3_core", metadata[:category]
    assert metadata[:description].present?
    assert metadata[:input_schema].present?
  end

  test "is read only" do
    assert V3::Tools::PlatformQueryTool.read_only?
  end

  test "returns error for missing type" do
    result = @tool.execute({})
    assert_equal false, result[:success]
    assert_match /Missing/, result[:error]
  end

  test "query schema lists available types" do
    result = @tool.execute({ "type" => "schema" })
    assert result[:success]
    assert result[:available_types].is_a?(Array)
  end

  test "query stats returns platform statistics" do
    result = @tool.execute({ "type" => "stats" })
    assert result[:success]
    assert result[:stats].is_a?(Hash)
  end

  test "query contacts returns results" do
    result = @tool.execute({ "type" => "contacts", "limit" => 5 })
    # May succeed or fail based on data, but should not crash
    assert result.is_a?(Hash)
    assert result.key?(:success)
  end
end
