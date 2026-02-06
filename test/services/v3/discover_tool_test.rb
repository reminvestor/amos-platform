# frozen_string_literal: true

require "test_helper"

class V3::Tools::DiscoverToolTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @entity = entities(:one)
    @tool = V3::Tools::DiscoverTool.new(user: @user, entity: @entity)
  end

  test "metadata has correct name" do
    metadata = V3::Tools::DiscoverTool.metadata
    assert_equal "discover", metadata[:name]
    assert_equal "v3_core", metadata[:category]
    assert metadata[:description].present?
  end

  test "is read only" do
    assert V3::Tools::DiscoverTool.read_only?
  end

  test "returns error for missing query" do
    result = @tool.execute({})
    assert_equal false, result[:success]
    assert_match /Missing/, result[:error]
  end

  test "searches features by keyword" do
    result = @tool.execute({ "query" => "landing page" })
    assert result[:success]
    assert result[:results].is_a?(Array)
  end

  test "searches by category" do
    result = @tool.execute({ "query" => "email", "category" => "features" })
    assert result[:success]
    assert result[:results].is_a?(Array)
  end

  test "returns empty results for unknown query" do
    result = @tool.execute({ "query" => "xyznonexistent123" })
    assert result[:success]
    assert_equal 0, result[:count]
  end
end
