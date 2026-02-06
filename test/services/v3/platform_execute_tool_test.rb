# frozen_string_literal: true

require "test_helper"

class V3::Tools::PlatformExecuteToolTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @entity = entities(:one)
    @tool = V3::Tools::PlatformExecuteTool.new(user: @user, entity: @entity)
  end

  test "metadata has correct name" do
    metadata = V3::Tools::PlatformExecuteTool.metadata
    assert_equal "platform_execute", metadata[:name]
    assert_equal "v3_core", metadata[:category]
    assert metadata[:description].present?
  end

  test "returns error for missing action" do
    result = @tool.execute({})
    assert_equal false, result[:success]
    assert_match /Missing/, result[:error]
  end

  test "returns error for unknown action" do
    result = @tool.execute({ "action" => "fly_to_moon" })
    assert_equal false, result[:success]
    assert_match /Unknown action/, result[:error]
    assert result[:available_actions].is_a?(Array)
  end

  test "integration action requires integration and operation" do
    result = @tool.execute({ "action" => "integration" })
    assert_equal false, result[:success]
    assert_match /Missing.*integration/i, result[:error]
  end

  test "send_campaign requires campaign_id" do
    result = @tool.execute({ "action" => "send_campaign" })
    assert_equal false, result[:success]
    assert_match /Missing.*campaign_id/i, result[:error]
  end

  test "publish_landing_page requires landing_page_id" do
    result = @tool.execute({ "action" => "publish_landing_page" })
    assert_equal false, result[:success]
    assert_match /Missing.*landing_page_id/i, result[:error]
  end
end
