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

  # ══════════════════════════════════════════════════════════════
  # DELETE
  # ══════════════════════════════════════════════════════════════

  test "delete requires type and id" do
    result = @tool.execute({ "action" => "delete" })
    assert_equal false, result[:success]
    assert_match /type/i, result[:error]
  end

  test "delete removes a contact" do
    contact = Contact.create!(entity: @entity, user: @user, first_name: "Del", last_name: "Test", email: "del@test.com")
    result = @tool.execute({ "action" => "delete", "type" => "contact", "id" => contact.id })
    assert result[:success] != false, "Should succeed: #{result[:error]}"
    refute Contact.exists?(id: contact.id)
  end

  test "delete rejects unsupported types" do
    result = @tool.execute({ "action" => "delete", "type" => "user", "id" => 1 })
    assert_equal false, result[:success]
    assert_match /Cannot delete/i, result[:error]
  end

  # ══════════════════════════════════════════════════════════════
  # GENERATE IMAGE
  # ══════════════════════════════════════════════════════════════

  test "generate_image requires prompt" do
    result = @tool.execute({ "action" => "generate_image" })
    assert_equal false, result[:success]
    assert_match /prompt/i, result[:error]
  end

  # ══════════════════════════════════════════════════════════════
  # AVAILABLE ACTIONS
  # ══════════════════════════════════════════════════════════════

  test "available_actions includes all actions" do
    result = @tool.execute({ "action" => "nonexistent" })
    actions = result[:available_actions]
    %w[integration send_campaign generate_file generate_image delete].each do |a|
      assert actions.include?(a), "Should include action: #{a}"
    end
  end
end
