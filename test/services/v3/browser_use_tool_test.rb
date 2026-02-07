# frozen_string_literal: true

require "test_helper"

class V3::Tools::BrowserUseToolTest < ActiveSupport::TestCase
  fixtures :users, :entities

  setup do
    @user = users(:one)
    @entity = entities(:one)
    @tool = V3::Tools::BrowserUseTool.new(user: @user, entity: @entity)
  end

  test "metadata has correct name and category" do
    metadata = V3::Tools::BrowserUseTool.metadata
    assert_equal "browser_use", metadata[:name]
    assert_equal "v3_core", metadata[:category]
    assert metadata[:description].present?
  end

  test "metadata lists all actions in enum" do
    schema = V3::Tools::BrowserUseTool.metadata[:input_schema]
    action_enum = schema[:properties][:action][:enum]

    %w[navigate click type scroll screenshot press_key wait page_state handoff_to_user resume_from_user close].each do |action|
      assert action_enum.include?(action), "Should include action: #{action}"
    end
  end

  test "returns error for missing action" do
    result = @tool.execute({})
    assert_equal false, result[:success]
    assert_match(/action/i, result[:error])
  end

  test "returns error for unknown action" do
    result = @tool.execute({ "action" => "teleport" })
    assert_equal false, result[:success]
    assert_match(/Unknown action/i, result[:error])
  end

  test "navigate requires url" do
    result = @tool.execute({ "action" => "navigate" })
    assert_equal false, result[:success]
    assert_match(/url/i, result[:error])
  end

  test "click requires selector" do
    result = @tool.execute({ "action" => "click" })
    assert_equal false, result[:success]
    assert_match(/selector/i, result[:error])
  end

  test "type requires selector and text" do
    result = @tool.execute({ "action" => "type", "selector" => "input" })
    assert_equal false, result[:success]
    assert_match(/text/i, result[:error])
  end

  test "press_key requires key" do
    result = @tool.execute({ "action" => "press_key" })
    assert_equal false, result[:success]
    assert_match(/key/i, result[:error])
  end
end
