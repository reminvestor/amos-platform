# frozen_string_literal: true

require 'test_helper'

class UnifiedPreprocessorServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # INTENT CLASSIFICATION
  # ═══════════════════════════════════════════════════════════════════════════

  test "classifies workflow creation as build intent" do
    preprocessor = build_preprocessor
    result = preprocessor.send(:classify_intent, "create a workflow that sends emails on form submit")
    assert_equal :build, result
  end

  test "classifies automation creation as build intent" do
    preprocessor = build_preprocessor
    result = preprocessor.send(:classify_intent, "build an automation to notify on record changes")
    assert_equal :build, result
  end

  test "classifies trigger setup as build intent" do
    preprocessor = build_preprocessor
    result = preprocessor.send(:classify_intent, "set up a trigger for form submissions")
    assert_equal :build, result
  end

  test "classifies natural workflow description as build intent" do
    preprocessor = build_preprocessor
    result = preprocessor.send(:classify_intent, "when a form is submitted, update the record and send an email")
    assert_equal :build, result
  end

  test "classifies automate pattern as build intent" do
    preprocessor = build_preprocessor
    result = preprocessor.send(:classify_intent, "automatically send a notification when a record is updated")
    assert_equal :build, result
  end

  test "classifies landing page creation as build intent" do
    preprocessor = build_preprocessor
    result = preprocessor.send(:classify_intent, "create a landing page for our product launch")
    assert_equal :build, result
  end

  test "classifies show contacts as view intent" do
    preprocessor = build_preprocessor
    result = preprocessor.send(:classify_intent, "show me my contacts")
    assert_equal :view, result
  end

  test "classifies create contact as create_data intent" do
    preprocessor = build_preprocessor
    result = preprocessor.send(:classify_intent, "create a new contact for John Smith")
    assert_equal :create_data, result
  end

  test "classifies greeting as unknown intent" do
    preprocessor = build_preprocessor
    result = preprocessor.send(:classify_intent, "hello there")
    assert_equal :unknown, result
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FAST PATH / CONVERSATION CONTEXT
  # ═══════════════════════════════════════════════════════════════════════════

  test "simple greeting takes fast path" do
    preprocessor = build_preprocessor
    classification = preprocessor.send(:quick_classify, "hi")
    result = preprocessor.send(:simple_conversational_message?, "hi", classification)
    assert result, "Simple greeting should take fast path"
  end

  test "yes takes fast path without conversation context" do
    preprocessor = build_preprocessor
    classification = preprocessor.send(:quick_classify, "yes")
    result = preprocessor.send(:simple_conversational_message?, "yes", classification)
    assert result, "'yes' without context should take fast path"
  end

  test "yes does NOT take fast path during workflow creation conversation" do
    conversation = [
      { role: 'assistant', content: "Here's how we'll build it: 1. Trigger: Form submission 2. Action: Create contact" },
      { role: 'user', content: 'yes lets do that!' }
    ]
    preprocessor = build_preprocessor(conversation_history: conversation)
    classification = preprocessor.send(:quick_classify, "yes lets do that!")
    result = preprocessor.send(:simple_conversational_message?, "yes lets do that!", classification)
    assert_not result, "'yes' during workflow creation should NOT take fast path"
  end

  test "ok does NOT take fast path during landing page design" do
    conversation = [
      { role: 'assistant', content: "I'll design the landing page with a hero section and CTA" },
      { role: 'user', content: 'ok sounds good' }
    ]
    preprocessor = build_preprocessor(conversation_history: conversation)
    classification = preprocessor.send(:quick_classify, "ok sounds good")
    result = preprocessor.send(:simple_conversational_message?, "ok sounds good", classification)
    assert_not result, "'ok' during landing page creation should NOT take fast path"
  end

  test "sure does NOT take fast path during automation discussion" do
    conversation = [
      { role: 'assistant', content: "I'll set up the automation trigger for when a contact is created" },
      { role: 'user', content: 'sure go ahead' }
    ]
    preprocessor = build_preprocessor(conversation_history: conversation)
    classification = preprocessor.send(:quick_classify, "sure go ahead")
    result = preprocessor.send(:simple_conversational_message?, "sure go ahead", classification)
    assert_not result, "'sure' during automation discussion should NOT take fast path"
  end

  test "yes takes fast path during casual conversation" do
    conversation = [
      { role: 'assistant', content: "Hi! How can I help you today?" },
      { role: 'user', content: 'yes please' }
    ]
    preprocessor = build_preprocessor(conversation_history: conversation)
    classification = preprocessor.send(:quick_classify, "yes please")
    result = preprocessor.send(:simple_conversational_message?, "yes please", classification)
    assert result, "'yes' during casual chat should take fast path"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # INTENT-BASED TOOLS
  # ═══════════════════════════════════════════════════════════════════════════

  test "build intent includes generate_automation_code" do
    tools = UnifiedPreprocessorService::INTENT_TOOLS[:build]
    assert_includes tools, 'generate_automation_code'
  end

  test "workflow design intent includes generate_automation_code" do
    tools = UnifiedPreprocessorService::LLM_DESIGN_INTENT_TOOLS[:workflow]
    assert_includes tools, 'generate_automation_code'
  end

  test "create mode includes generate_automation_code" do
    tools = UnifiedPreprocessorService::LLM_MODE_TOOLS[:create]
    assert_includes tools, 'generate_automation_code'
  end

  test "view intent does not include generate_automation_code" do
    tools = UnifiedPreprocessorService::INTENT_TOOLS[:view]
    assert_not_includes tools, 'generate_automation_code'
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CONVERSATION CONTEXT DETECTION
  # ═══════════════════════════════════════════════════════════════════════════

  test "detects workflow context in conversation" do
    conversation = [
      { role: 'assistant', content: "I'll create the workflow with a form submission trigger" }
    ]
    preprocessor = build_preprocessor(conversation_history: conversation)
    assert preprocessor.send(:conversation_has_active_creation_context?)
  end

  test "detects automation context in conversation" do
    conversation = [
      { role: 'assistant', content: "The automation will auto-create a contact when triggered" }
    ]
    preprocessor = build_preprocessor(conversation_history: conversation)
    assert preprocessor.send(:conversation_has_active_creation_context?)
  end

  test "detects module design context in conversation" do
    conversation = [
      { role: 'assistant', content: "Let me propose the module design schema for your app" }
    ]
    preprocessor = build_preprocessor(conversation_history: conversation)
    assert preprocessor.send(:conversation_has_active_creation_context?)
  end

  test "no context detected in casual conversation" do
    conversation = [
      { role: 'assistant', content: "Hi! How can I help you today?" },
      { role: 'user', content: "what's the weather?" }
    ]
    preprocessor = build_preprocessor(conversation_history: conversation)
    assert_not preprocessor.send(:conversation_has_active_creation_context?)
  end

  test "handles empty conversation history" do
    preprocessor = build_preprocessor(conversation_history: [])
    assert_not preprocessor.send(:conversation_has_active_creation_context?)
  end

  test "handles nil conversation history" do
    preprocessor = build_preprocessor(conversation_history: nil)
    assert_not preprocessor.send(:conversation_has_active_creation_context?)
  end

  test "handles array content blocks in conversation" do
    conversation = [
      { role: 'assistant', content: [{ type: 'text', text: 'Here is the workflow trigger setup' }] }
    ]
    preprocessor = build_preprocessor(conversation_history: conversation)
    assert preprocessor.send(:conversation_has_active_creation_context?)
  end

  private

  def build_preprocessor(conversation_history: nil)
    UnifiedPreprocessorService.new(
      user: @user,
      entity: @entity,
      conversation_history: conversation_history
    )
  end
end
