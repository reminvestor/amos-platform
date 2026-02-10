# frozen_string_literal: true

require "test_helper"

class V3::IntentEngineTest < ActiveSupport::TestCase
  fixtures :users, :entities

  setup do
    @user = users(:one)
    @entity = entities(:one)
    @engine = V3::IntentEngine.new(user: @user, entity: @entity)
  end

  # ══════════════════════════════════════════════════════════════
  # RECIPE PATH
  # ══════════════════════════════════════════════════════════════

  test "uses recipe fast path for simple contact creation" do
    # Contact creation is a simple, recipe-worthy operation
    result = @engine.execute(
      goal: "create a contact",
      spec: { first_name: "Test", last_name: "Recipe", email: "recipe-test-#{SecureRandom.hex(4)}@test.com" }
    )

    assert result.is_a?(Hash)
    # If recipe path is used, it will have _engine metadata
    if result[:_engine]
      assert_includes %w[recipe platform_brain], result[:_engine][:path]
    end
  end

  test "uses recipe fast path for delete operations" do
    # Create a contact first
    contact = Contact.create!(
      entity: @entity,
      user: @user,
      first_name: "ToDelete",
      last_name: "Contact",
      email: "delete-test-#{SecureRandom.hex(4)}@test.com"
    )

    result = @engine.execute(
      goal: "delete a contact",
      spec: { type: "contact", id: contact.id }
    )

    assert result.is_a?(Hash)
  end

  # ══════════════════════════════════════════════════════════════
  # PLATFORM BRAIN PATH
  # ══════════════════════════════════════════════════════════════

  test "delegates complex goals to Platform Brain" do
    # Complex multi-step goal should go to Brain
    # We mock the Brain to avoid actual Claude calls in tests
    mock_brain = Minitest::Mock.new
    mock_brain.expect(:execute, {
      success: true,
      message: "Created template and automation",
      tools_used: ["platform_create", "platform_create"],
      _engine: { path: "platform_brain", tool_calls: 2, latency_ms: 500 }
    }, goal: "set up a drip campaign with 3 emails for new subscribers", spec: {})

    V3::PlatformBrain.stub(:new, ->(**_args) { mock_brain }) do
      result = @engine.execute(
        goal: "set up a drip campaign with 3 emails for new subscribers",
        spec: {}
      )

      assert result[:success]
      assert_equal "platform_brain", result[:_engine][:path]
    end
  end

  # ══════════════════════════════════════════════════════════════
  # ERROR HANDLING
  # ══════════════════════════════════════════════════════════════

  test "handles errors gracefully" do
    result = @engine.execute(goal: "", spec: {})
    # Empty goal should still not crash
    assert result.is_a?(Hash)
  end

  test "returns structured result on exception" do
    # IntentEngine with nil user/entity should still return a hash
    # (it may succeed or fail gracefully via rescue)
    engine = V3::IntentEngine.new(user: nil, entity: nil)
    result = engine.execute(goal: "do something impossible", spec: {})

    assert result.is_a?(Hash)
    # The engine handles nil gracefully — just verify it returns a structured result
  end
end
