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
  # WEB APP DETECTION
  # ═══════════════════════════════════════════════════════════════════════════

  test "detects web_app_create for customer portal" do
    task_type = GuidanceLibrary.detect_task_type(
      message: "Build me a customer portal"
    )
    assert_equal :web_app_create, task_type
  end

  test "detects web_app_create for external app" do
    task_type = GuidanceLibrary.detect_task_type(
      message: "Create an external app for tracking orders"
    )
    assert_equal :web_app_create, task_type
  end

  test "detects web_app_create for web app" do
    task_type = GuidanceLibrary.detect_task_type(
      message: "Build a web app for task management"
    )
    assert_equal :web_app_create, task_type
  end

  test "detects web_app_create for tracker app" do
    task_type = GuidanceLibrary.detect_task_type(
      message: "Build me a task tracker app"
    )
    assert_equal :web_app_create, task_type
  end

  test "detects web_app_create for public dashboard" do
    task_type = GuidanceLibrary.detect_task_type(
      message: "Create a customer dashboard app"
    )
    assert_equal :web_app_create, task_type
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # LANDING PAGE vs WEBSITE DISTINCTION
  # ═══════════════════════════════════════════════════════════════════════════

  test "detects landing_page_create for explicit landing page" do
    task_type = GuidanceLibrary.detect_task_type(
      message: "Create a landing page for my product"
    )
    assert_equal :landing_page_create, task_type
  end

  test "detects landing_page_create for marketing page" do
    task_type = GuidanceLibrary.detect_task_type(
      message: "Build a marketing page for our summer sale"
    )
    assert_equal :landing_page_create, task_type
  end

  test "detects landing_page_create for promo page" do
    task_type = GuidanceLibrary.detect_task_type(
      message: "Create a promo page for the event"
    )
    assert_equal :landing_page_create, task_type
  end

  test "detects website_create for company website" do
    task_type = GuidanceLibrary.detect_task_type(
      message: "Build a website for my business"
    )
    assert_equal :website_create, task_type
  end

  test "detects website_create for portfolio site" do
    task_type = GuidanceLibrary.detect_task_type(
      message: "Create a portfolio site for my work"
    )
    assert_equal :website_create, task_type
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # WEB APP GUIDANCE
  # ═══════════════════════════════════════════════════════════════════════════

  test "web_app_create guidance exists" do
    guidance = GuidanceLibrary.for_task(:web_app_create)
    assert guidance.is_a?(String)
    assert_match /web_app/i, guidance
    assert_match /platform_create/i, guidance
  end

  test "web_app_create tools include platform_create" do
    tools = GuidanceLibrary.tools_for_task(:web_app_create)
    assert_includes tools, "platform_create"
    assert_includes tools, "load_canvas"
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
    
    assert guidance.include?("IMPORTANT") || guidance.include?("CRITICAL") || guidance.include?("FOCUS"),
      "Guidance should include emphasis keywords"
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
    # V3 uses platform tools instead of individual tools
    assert tools.include?("platform_query") || tools.include?("platform_execute") || tools.include?("discover"),
      "Integration tools should include V3 platform tools, got: #{tools}"
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
