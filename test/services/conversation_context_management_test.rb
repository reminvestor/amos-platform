# frozen_string_literal: true

require "test_helper"

class ConversationContextManagementTest < ActiveSupport::TestCase
  # ═══════════════════════════════════════════════════════════════════════════
  # Topic Detection Tests
  # ═══════════════════════════════════════════════════════════════════════════

  def setup
    @user = users(:one)
    @entity = entities(:one)
    @session_id = "test_session_#{SecureRandom.hex(8)}"
    
    # Create a mock service for testing
    @service = ScoutGenericToolsServiceV2.new(
      @user,
      @entity,
      @session_id
    )
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Topic Change Detection
  # ─────────────────────────────────────────────────────────────────────────────

  test "detects topic change when user explicitly switches topics" do
    history = [
      { "role" => "user", "content" => "Build me a landing page for my fitness app" },
      { "role" => "assistant", "content" => "I've created a design plan for your landing page." },
      { "role" => "user", "content" => "That looks great!" },
      { "role" => "assistant", "content" => "Happy to help! Want me to build it?" }
    ]
    
    # Explicit topic change
    current_message = "Actually, forget about that. What are macro and micro trends?"
    
    result = @service.send(:detect_topic_change, current_message, history)
    assert result, "Should detect topic change when user says 'forget about that'"
  end

  test "detects topic change when switching from build mode to general question" do
    history = [
      { "role" => "user", "content" => "Create a landing page for my SaaS product" },
      { "role" => "assistant", "content" => "I've created a design plan with sections for hero, features, pricing." },
      { "role" => "user", "content" => "Looks good, let's build it" },
      { "role" => "assistant", "content" => "Building your landing page now..." }
    ]
    
    # New topic - asking about market trends
    current_message = "What are the current market trends in my industry?"
    
    result = @service.send(:detect_topic_change, current_message, history)
    assert result, "Should detect topic change from build mode to general question"
  end

  test "does not detect topic change when user wants to return to previous topic" do
    history = [
      { "role" => "user", "content" => "Build me a landing page" },
      { "role" => "assistant", "content" => "Created a design plan for you" },
      { "role" => "user", "content" => "What are market trends?" },
      { "role" => "assistant", "content" => "Here are some trends..." }
    ]
    
    # User returning to the plan
    current_message = "Back to the landing page plan - can we add testimonials?"
    
    result = @service.send(:detect_topic_change, current_message, history)
    assert_not result, "Should NOT detect topic change when user says 'back to'"
  end

  test "does not detect topic change when continuing same topic" do
    history = [
      { "role" => "user", "content" => "Build me a landing page" },
      { "role" => "assistant", "content" => "Created a design plan for you" }
    ]
    
    # Continuing same topic
    current_message = "Can you make the hero section more colorful?"
    
    result = @service.send(:detect_topic_change, current_message, history)
    assert_not result, "Should NOT detect topic change when continuing same topic"
  end

  test "does not detect topic change on short history" do
    history = [
      { "role" => "user", "content" => "Hello" },
      { "role" => "assistant", "content" => "Hi there!" }
    ]
    
    current_message = "What are market trends?"
    
    result = @service.send(:detect_topic_change, current_message, history)
    assert_not result, "Should NOT detect topic change with insufficient history"
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Tool Artifact Cleaning
  # ─────────────────────────────────────────────────────────────────────────────

  test "cleans plan_design tool references from content" do
    content = "I called plan_design(action: 'create', type: 'landing_page') to create your plan."
    
    cleaned = @service.send(:clean_tool_mode_artifacts, content)
    
    assert_not_includes cleaned, "plan_design("
    assert_includes cleaned, "[tool action]"
  end

  test "cleans 'I've created a design plan' messages" do
    content = "I've created a design plan for your landing page. It includes these sections..."
    
    cleaned = @service.send(:clean_tool_mode_artifacts, content)
    
    assert_not_includes cleaned.downcase, "i've created a design plan"
  end

  test "cleans JSON plan data that leaked into messages" do
    content = 'Here is the plan {"sections": [{"type": "hero"}]} that I created.'
    
    cleaned = @service.send(:clean_tool_mode_artifacts, content)
    
    assert_includes cleaned, "[plan data]"
    assert_not_includes cleaned, '"sections"'
  end

  test "preserves normal content without tool artifacts" do
    content = "Here are the current market trends: 1. AI adoption is growing. 2. Remote work is here to stay."
    
    cleaned = @service.send(:clean_tool_mode_artifacts, content)
    
    assert_equal content, cleaned.strip
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Context Extraction
  # ─────────────────────────────────────────────────────────────────────────────

  test "extracts document IDs from conversation" do
    history = [
      { "role" => "user", "content" => "Read document asset_id: 123" },
      { "role" => "assistant", "content" => "I found document 'Report.pdf' (asset_id: 456)" }
    ]
    
    context = @service.send(:extract_working_context, history)
    
    assert_includes context[:documents], 123
    # Note: The hash format might be different
  end

  test "extracts landing page IDs from conversation" do
    history = [
      { "role" => "user", "content" => "Show me landing_page_id: 789" },
      { "role" => "assistant", "content" => "Here's your landing page" }
    ]
    
    context = @service.send(:extract_working_context, history)
    
    assert_includes context[:landing_pages], 789
  end
end

class IntentClassifierTopicAwarenessTest < ActiveSupport::TestCase
  # ═══════════════════════════════════════════════════════════════════════════
  # Intent Classifier Topic Awareness Tests
  # ═══════════════════════════════════════════════════════════════════════════

  def setup
    @entity = entities(:one)
    @classifier = IntentClassifierService.new(entity: @entity)
  end

  test "detects returning to previous topic" do
    assert @classifier.send(:returning_to_previous_topic?, "back to the plan")
    assert @classifier.send(:returning_to_previous_topic?, "let's continue with that")
    assert @classifier.send(:returning_to_previous_topic?, "about that landing page")
    
    assert_not @classifier.send(:returning_to_previous_topic?, "what are market trends?")
    assert_not @classifier.send(:returning_to_previous_topic?, "build me a new page")
  end

  test "filters history for mode classification" do
    history = [
      { role: "user", content: "Build me a landing page" },
      { role: "assistant", content: "I've created a design plan for your landing page using plan_design(action: 'create')" },
      { role: "user", content: "Looks good" },
      { role: "assistant", content: "Here's the plan for your consideration" }
    ]
    
    filtered = @classifier.send(:filter_history_for_mode_classification, history)
    
    # Should have cleaned out tool references
    filtered.each do |msg|
      assert_not_includes msg[:content], "plan_design("
      assert_not_includes msg[:content].downcase, "i've created a design plan"
    end
  end

  test "classifies ideate mode for general questions" do
    result = @classifier.classify_mode(message: "What do you think about market trends?")
    
    assert_equal :ideate, result[:mode]
  end

  test "classifies create mode for build requests" do
    result = @classifier.classify_mode(message: "Build me a landing page for my app")
    
    assert_equal :create, result[:mode]
  end

  test "classifies operate mode for viewing requests" do
    result = @classifier.classify_mode(message: "Show me my landing pages")
    
    assert_equal :operate, result[:mode]
  end
end

class ConversationSummaryTest < ActiveSupport::TestCase
  # ═══════════════════════════════════════════════════════════════════════════
  # Conversation Summary Tests
  # ═══════════════════════════════════════════════════════════════════════════

  def setup
    @user = users(:one)
    @entity = entities(:one)
    @session_id = "test_session_#{SecureRandom.hex(8)}"
  end

  test "needs_summarization returns false for short conversations" do
    # Create a few messages
    5.times do |i|
      ScoutMessage.create!(
        user: @user,
        entity: @entity,
        session_id: @session_id,
        role: i.even? ? "user" : "assistant",
        content: "Message #{i}"
      )
    end
    
    result = ConversationSummary.needs_summarization?(session_id: @session_id)
    
    assert_not result, "Should not need summarization for short conversations"
  end

  test "for_prompt returns empty string when no summaries exist" do
    result = ConversationSummary.for_prompt(session_id: @session_id)
    
    assert_equal "", result
  end

  test "for_prompt formats summaries correctly" do
    # Create a summary
    ConversationSummary.create!(
      user: @user,
      entity: @entity,
      session_id: @session_id,
      summary: "User discussed building a landing page for their fitness app.",
      key_topics: ["landing page", "fitness"].to_json,
      key_decisions: ["Use blue color scheme"].to_json,
      action_items: ["Add testimonials section"].to_json,
      context_for_future: "User prefers minimalist design",
      message_start_index: 1,
      message_end_index: 20,
      messages_summarized: 20,
      original_tokens: 1000,
      summary_tokens: 100,
      model_used: "claude-haiku-4-5-20251001",
      active: true
    )
    
    result = ConversationSummary.for_prompt(session_id: @session_id)
    
    assert_includes result, "CONVERSATION HISTORY SUMMARY"
    assert_includes result, "landing page"
    assert_includes result, "fitness"
    assert_includes result, "minimalist design"
  end
end
