# frozen_string_literal: true

require "test_helper"

class GuidanceLibraryTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TASK TYPE DETECTION
  # ═══════════════════════════════════════════════════════════════════════════

  test "detects landing_page_edit from canvas context" do
    task_type = GuidanceLibrary.detect_task_type(
      canvas_context: { type: "landing_page_editor" }
    )
    
    assert_equal :landing_page_edit, task_type
  end

  test "detects integration_setup from message" do
    task_type = GuidanceLibrary.detect_task_type(
      message: "Connect my Stripe account"
    )
    
    assert_equal :integration_setup, task_type
  end

  test "detects workflow_design from canvas" do
    task_type = GuidanceLibrary.detect_task_type(
      canvas_context: { type: "workflow_designer" }
    )
    
    assert_equal :workflow_design, task_type
  end

  test "returns general for unknown context" do
    task_type = GuidanceLibrary.detect_task_type(
      message: "Hello, how are you?"
    )
    
    assert_equal :general, task_type
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GUIDANCE RETRIEVAL (WITHOUT ENTITY)
  # ═══════════════════════════════════════════════════════════════════════════

  test "for_task returns guidance for valid task type" do
    guidance = GuidanceLibrary.for_task(:integration_setup)
    
    assert guidance.is_a?(String)
    assert guidance.include?("CURRENT FOCUS")
    assert guidance.include?("Integration")
  end

  test "for_task returns nil for general task type" do
    guidance = GuidanceLibrary.for_task(:general)
    
    assert_nil guidance
  end

  test "for_task includes anti-hallucination reminder" do
    guidance = GuidanceLibrary.for_task(:integration_setup)
    
    assert guidance.include?("IMPORTANT")
    assert guidance.include?("list_integration_actions")
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GUIDANCE WITH LEARNED EXPERIENCES
  # ═══════════════════════════════════════════════════════════════════════════

  test "for_task with entity includes learned experiences" do
    guidance = GuidanceLibrary.for_task(:integration_setup, entity: @entity)
    
    assert guidance.is_a?(String)
    assert guidance.include?("CURRENT FOCUS")
    
    # Should include learned experiences section
    assert guidance.include?("LEARNED EXPERIENCES"), 
           "Should include learned experiences when entity has them"
  end

  test "for_task with entity includes experience content" do
    guidance = GuidanceLibrary.for_task(:integration_setup, entity: @entity)
    
    # Our fixture has this content
    assert guidance.include?("list_integration_actions") || 
           guidance.include?("verify"),
           "Should include content from learned experiences"
  end

  test "for_task without experiences still works" do
    # Use a task type with no experiences
    guidance = GuidanceLibrary.for_task(:analytics_review, entity: @entity)
    
    assert guidance.is_a?(String)
    assert guidance.include?("CURRENT FOCUS")
    # Should NOT have learned experiences section (no data)
    assert_not guidance.include?("LEARNED EXPERIENCES"), 
               "Should not include learned experiences section when none exist"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TOOLS FOR TASK
  # ═══════════════════════════════════════════════════════════════════════════

  test "tools_for_task returns correct tools" do
    tools = GuidanceLibrary.tools_for_task(:integration_setup)
    
    assert tools.is_a?(Array)
    assert tools.include?("list_connections")
    assert tools.include?("execute_integration_action")
  end

  test "tools_for_task returns empty array for general" do
    tools = GuidanceLibrary.tools_for_task(:general)
    
    assert_equal [], tools
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # INJECT LEARNED EXPERIENCES
  # ═══════════════════════════════════════════════════════════════════════════

  test "inject_learned_experiences returns formatted string" do
    result = GuidanceLibrary.inject_learned_experiences(:integration_setup, @entity)
    
    assert result.is_a?(String) || result.nil?
    
    if result
      assert result.include?("LEARNED EXPERIENCES")
      assert result.include?("[1]")  # Should have numbered items
    end
  end

  test "inject_learned_experiences returns nil when no experiences" do
    result = GuidanceLibrary.inject_learned_experiences(:document_analysis, @entity)
    
    assert_nil result
  end
end
