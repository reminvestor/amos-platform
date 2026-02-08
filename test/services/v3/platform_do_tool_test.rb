# frozen_string_literal: true

require "test_helper"

class V3::Tools::PlatformDoToolTest < ActiveSupport::TestCase
  fixtures :users, :entities

  setup do
    @user = users(:one)
    @entity = entities(:one)
    @tool = V3::Tools::PlatformDoTool.new(user: @user, entity: @entity)
  end

  # ══════════════════════════════════════════════════════════════
  # METADATA
  # ══════════════════════════════════════════════════════════════

  test "metadata has correct name and category" do
    metadata = V3::Tools::PlatformDoTool.metadata
    assert_equal "platform_do", metadata[:name]
    assert_equal "v3_core", metadata[:category]
    assert metadata[:description].present?
  end

  test "metadata requires goal parameter" do
    schema = V3::Tools::PlatformDoTool.metadata[:input_schema]
    assert_includes schema[:required], "goal"
  end

  test "description includes usage examples" do
    desc = V3::Tools::PlatformDoTool.metadata[:description]
    assert desc.include?("create contact"), "Should include contact example"
    assert desc.include?("welcome email"), "Should include email automation example"
    assert desc.include?("landing page"), "Should include landing page example"
    assert desc.include?("build app"), "Should include app example"
  end

  # ══════════════════════════════════════════════════════════════
  # VALIDATION
  # ══════════════════════════════════════════════════════════════

  test "returns error for missing goal" do
    result = @tool.execute({ "spec" => { "name" => "test" } })
    assert_equal false, result[:success]
    assert_match(/goal/i, result[:error])
  end

  test "returns error for blank goal" do
    result = @tool.execute({ "goal" => "", "spec" => {} })
    assert_equal false, result[:success]
    assert_match(/goal/i, result[:error])
  end

  # ══════════════════════════════════════════════════════════════
  # INTENT ENGINE DELEGATION
  # ══════════════════════════════════════════════════════════════

  test "delegates to IntentEngine" do
    # Mock IntentEngine to verify delegation
    mock_engine = Minitest::Mock.new
    mock_engine.expect(:execute, { success: true, message: "Done" }, goal: "create contact", spec: { "first_name" => "Jane" })

    V3::IntentEngine.stub(:new, ->(**_args) { mock_engine }) do
      result = @tool.execute({
        "goal" => "create contact",
        "spec" => { "first_name" => "Jane" }
      })

      assert result[:success] != false
    end
  end

  test "handles spec with string and symbol keys" do
    # The tool should normalize specs regardless of key type
    result = @tool.execute({
      "goal" => "create contact",
      "spec" => { "first_name" => "Jane", email: "jane@test.com" }
    })

    # Should not raise -- just verifying it processes without error
    assert result.is_a?(Hash)
  end
end
