# frozen_string_literal: true

require "test_helper"

class Amos::SessionFocusTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @entity = entities(:one)
    @session_id = "test_session_#{SecureRandom.hex(8)}"
    
    @focus = Amos::SessionFocus.new(
      session_id: @session_id,
      user: @user,
      entity: @entity
    )
    
    # Clean up any existing focus for this session
    @focus.clear_focus
  end

  def teardown
    @focus.clear_focus
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Core Operations
  # ─────────────────────────────────────────────────────────────────────────────

  test "set_focus stores focus data in Redis" do
    result = @focus.set_focus(
      type: :landing_page,
      id: 123,
      name: "My Landing Page"
    )
    
    assert result
    assert @focus.focused?
  end

  test "get_focus returns stored focus data" do
    @focus.set_focus(type: :landing_page, id: 123, name: "My LP")
    
    data = @focus.get_focus
    
    assert_equal :landing_page, data[:type]
    assert_equal 123, data[:id]
    assert_equal "My LP", data[:name]
    assert data[:set_at].present?
  end

  test "clear_focus removes focus from Redis" do
    @focus.set_focus(type: :landing_page, id: 123)
    assert @focus.focused?
    
    @focus.clear_focus
    
    assert_not @focus.focused?
    assert_nil @focus.get_focus
  end

  test "focused_on? checks focus type" do
    @focus.set_focus(type: :design_plan, id: 456)
    
    assert @focus.focused_on?(:design_plan)
    assert_not @focus.focused_on?(:landing_page)
  end

  test "set_focus rejects invalid focus types" do
    result = @focus.set_focus(type: :invalid_type, id: 123)
    
    assert_not result
    assert_not @focus.focused?
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Context
  # ─────────────────────────────────────────────────────────────────────────────

  test "set_focus stores context data" do
    @focus.set_focus(
      type: :design_plan,
      id: 123,
      name: "My Plan",
      context: { sections: ["hero", "features"], status: "draft" }
    )
    
    data = @focus.get_focus
    
    assert_equal ["hero", "features"], data[:context][:sections]
    assert_equal "draft", data[:context][:status]
  end

  test "update_context merges new context" do
    @focus.set_focus(
      type: :landing_page,
      id: 123,
      context: { status: "draft" }
    )
    
    @focus.update_context(sections: ["hero", "cta"])
    
    data = @focus.get_focus
    assert_equal "draft", data[:context][:status]
    assert_equal ["hero", "cta"], data[:context][:sections]
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Prompt Formatting
  # ─────────────────────────────────────────────────────────────────────────────

  test "format_for_prompt returns empty string when no focus" do
    result = @focus.format_for_prompt
    
    assert_equal "", result
  end

  test "format_for_prompt includes focus details" do
    @focus.set_focus(
      type: :landing_page,
      id: 123,
      name: "Fitness App LP",
      context: { plan_id: 456, sections: ["hero", "features"] }
    )
    
    result = @focus.format_for_prompt
    
    assert_includes result, "CURRENT FOCUS"
    assert_includes result, "Landing Page"
    assert_includes result, "#123"
    assert_includes result, "Fitness App LP"
    assert_includes result, "Design Plan: #456"
    assert_includes result, "hero, features"
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Convenience Methods
  # ─────────────────────────────────────────────────────────────────────────────

  test "focus_on_design_plan sets focus with plan details" do
    # Create a mock plan
    plan = OpenStruct.new(
      id: 789,
      name: "My Design Plan",
      design_type: "landing_page",
      status: "draft",
      sections: [{ "name" => "hero" }, { "name" => "features" }]
    )
    
    @focus.focus_on_design_plan(plan)
    
    data = @focus.get_focus
    assert_equal :design_plan, data[:type]
    assert_equal 789, data[:id]
    assert_includes data[:context][:sections], "hero"
  end

  test "focus_on_landing_page sets focus with landing page details" do
    # Create a mock landing page
    landing_page = OpenStruct.new(
      id: 321,
      title: "My LP Title",
      status: "published"
    )
    
    @focus.focus_on_landing_page(landing_page)
    
    data = @focus.get_focus
    assert_equal :landing_page, data[:type]
    assert_equal 321, data[:id]
    assert_equal "published", data[:context][:status]
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Session Isolation
  # ─────────────────────────────────────────────────────────────────────────────

  test "different sessions have independent focus" do
    other_session = "other_session_#{SecureRandom.hex(8)}"
    other_focus = Amos::SessionFocus.new(session_id: other_session)
    
    @focus.set_focus(type: :landing_page, id: 111)
    other_focus.set_focus(type: :design_plan, id: 222)
    
    assert_equal 111, @focus.get_focus[:id]
    assert_equal 222, other_focus.get_focus[:id]
    
    other_focus.clear_focus
  end
end
