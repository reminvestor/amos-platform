# frozen_string_literal: true

require "test_helper"

class DynamicContextServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @service = DynamicContextService.new(user: @user, entity: @entity)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # INITIALIZATION
  # ═══════════════════════════════════════════════════════════════════════════

  test "initializes with user and entity" do
    assert_equal @user, @service.user
    assert_equal @entity, @service.entity
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # BUILD CONTEXT
  # ═══════════════════════════════════════════════════════════════════════════

  test "build_context returns hash with required keys" do
    context = @service.build_context(
      canvas_context: nil,
      message: "Hello"
    )

    assert context.is_a?(Hash)
    assert context.key?(:task_type)
    assert context.key?(:guidance_block)
    assert context.key?(:priority_tools)
    assert context.key?(:context_summary)
  end

  test "build_context detects landing_page_edit from canvas" do
    context = @service.build_context(
      canvas_context: { type: 'landing_page_editor', landing_page_id: 123 }
    )

    assert_equal :landing_page_edit, context[:task_type]
  end

  test "build_context detects integration_setup from message" do
    context = @service.build_context(
      message: "Connect my Stripe account"
    )

    assert_equal :integration_setup, context[:task_type]
  end

  test "build_context detects workflow_design from canvas" do
    context = @service.build_context(
      canvas_context: { type: 'workflow_designer' }
    )

    assert_equal :workflow_design, context[:task_type]
  end

  test "build_context returns general for unknown context" do
    context = @service.build_context(
      message: "Hello, how are you?"
    )

    assert_equal :general, context[:task_type]
  end

  test "build_context includes guidance_block for known task types" do
    context = @service.build_context(
      canvas_context: { type: 'landing_page_editor' }
    )

    assert context[:guidance_block].present?
    assert context[:guidance_block].include?("CURRENT FOCUS")
  end

  test "build_context includes priority_tools for task type" do
    context = @service.build_context(
      canvas_context: { type: 'landing_page_editor' }
    )

    assert context[:priority_tools].is_a?(Array)
    assert context[:priority_tools].any?, "Should have priority tools for landing_page_edit"
  end

  test "build_context includes context_summary" do
    context = @service.build_context(
      canvas_context: { type: 'landing_page_editor' }
    )

    assert context[:context_summary].present?
    assert context[:context_summary].include?("Task")
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # LEARNED EXPERIENCES INTEGRATION
  # ═══════════════════════════════════════════════════════════════════════════

  test "build_context includes learned experiences when available" do
    # Use entity with experiences from fixtures
    context = @service.build_context(
      canvas_context: { type: 'integrations_manager' },
      message: "Set up an integration"
    )

    # If experiences exist for this task type, they should be included
    if TaskExperience.for_entity(@entity).for_task_type("integration_setup").active.any?
      assert context[:guidance_block]&.include?("LEARNED EXPERIENCES") ||
             context[:guidance_block]&.include?("list_integration_actions"),
             "Should include learned experiences in guidance"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SELECT TOOLS FOR TASK
  # ═══════════════════════════════════════════════════════════════════════════

  test "select_tools_for_task returns array" do
    tools = @service.select_tools_for_task(:landing_page_edit)

    assert tools.is_a?(Array)
  end

  test "select_tools_for_task includes priority tools" do
    tools = @service.select_tools_for_task(:landing_page_edit)

    # Should include V3 platform tools for landing page editing
    assert tools.any?, "Should have tools for landing_page_edit task"
  end

  test "select_tools_for_task merges with base_tools" do
    base_tools = ["custom_tool_1", "custom_tool_2"]
    tools = @service.select_tools_for_task(:general, base_tools: base_tools)

    assert tools.include?("custom_tool_1")
    assert tools.include?("custom_tool_2")
  end

  test "select_tools_for_task removes duplicates" do
    base_tools = ["edit_landing_page_section"]
    tools = @service.select_tools_for_task(:landing_page_edit, base_tools: base_tools)

    # Should not have duplicates
    assert_equal tools.uniq.length, tools.length
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # HAS CONTEXT
  # ═══════════════════════════════════════════════════════════════════════════

  test "has_context returns true for specific canvas" do
    result = @service.has_context?(
      canvas_context: { type: 'landing_page_editor' }
    )

    assert result
  end

  test "has_context returns true for specific message" do
    result = @service.has_context?(
      message: "Create a new landing page"
    )

    assert result
  end

  test "has_context returns false for general conversation" do
    result = @service.has_context?(
      message: "Hello, how are you?"
    )

    assert_not result
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # BACKWARDS COMPATIBILITY
  # ═══════════════════════════════════════════════════════════════════════════

  test "build_context includes backwards compatibility keys" do
    context = @service.build_context(message: "test")

    # These keys are for backwards compatibility with old code
    assert context.key?(:plugin)
    assert context.key?(:plugin_slug)
    assert context.key?(:plugin_name)
    assert context.key?(:prompt_block)
    assert context.key?(:tools)
    assert context.key?(:tool_names)
    assert context.key?(:injection_reason)
  end
end
