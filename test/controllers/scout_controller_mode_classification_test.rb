require "test_helper"

class ScoutControllerModeClassificationTest < ActionDispatch::IntegrationTest
  # ═══════════════════════════════════════════════════════════════════════════
  # quick_classify_mode Tests - Fast regex-based mode classification
  # ═══════════════════════════════════════════════════════════════════════════
  #
  # Tests the quick_classify_mode helper method that provides instant mode
  # classification without LLM calls. This is used to pre-classify mode
  # before the orchestrator to avoid duplicate LLM calls.
  
  setup do
    @controller = ScoutController.new
  end
  
  # ─────────────────────────────────────────────────────────────────────────────
  # Personal Mode Detection
  # ─────────────────────────────────────────────────────────────────────────────
  
  test "classifies personal topics with high confidence" do
    personal_messages = [
      "what's the weather like today?",
      "tell me a recipe for dinner",
      "how are you doing?",
      "hey amos, what's up?",
      "this is personal, not work related"
    ]
    
    personal_messages.each do |msg|
      result = @controller.send(:quick_classify_mode, msg)
      assert_equal :personal, result[:mode], "Expected '#{msg}' to be classified as personal"
      assert_equal :high, result[:confidence]
    end
  end
  
  # ─────────────────────────────────────────────────────────────────────────────
  # Ideate Mode Detection
  # ─────────────────────────────────────────────────────────────────────────────
  
  test "classifies brainstorming topics with high confidence" do
    ideate_messages = [
      "let's brainstorm some ideas for the campaign",
      "help me think about our marketing strategy",
      "what do you think about this approach?",
      "give me some ideas for the landing page",
      "help me figure out the best approach"
    ]
    
    ideate_messages.each do |msg|
      result = @controller.send(:quick_classify_mode, msg)
      assert_equal :ideate, result[:mode], "Expected '#{msg}' to be classified as ideate"
      assert_equal :high, result[:confidence]
    end
  end
  
  # ─────────────────────────────────────────────────────────────────────────────
  # Create Mode Detection
  # ─────────────────────────────────────────────────────────────────────────────
  
  test "classifies creation requests with high confidence" do
    create_messages = [
      "create a landing page for my product",
      "build me an email campaign",
      "make a new workflow for leads",
      "design a signup form",
      "generate a new automation",
      "let's build an integration"
    ]
    
    create_messages.each do |msg|
      result = @controller.send(:quick_classify_mode, msg)
      assert_equal :create, result[:mode], "Expected '#{msg}' to be classified as create"
      assert_equal :high, result[:confidence]
    end
  end
  
  # ─────────────────────────────────────────────────────────────────────────────
  # Operate Mode (Default)
  # ─────────────────────────────────────────────────────────────────────────────
  
  test "classifies general business queries as operate" do
    operate_messages = [
      "show me my contacts",
      "how many leads do I have?",
      "what's the status of my campaigns?",
      "send an email to john@example.com",
      "update the contact record"
    ]
    
    operate_messages.each do |msg|
      result = @controller.send(:quick_classify_mode, msg)
      assert_equal :operate, result[:mode], "Expected '#{msg}' to be classified as operate"
    end
  end
  
  test "returns operate with low confidence for blank messages" do
    result = @controller.send(:quick_classify_mode, "")
    assert_equal :operate, result[:mode]
    assert_equal :low, result[:confidence]
    
    result = @controller.send(:quick_classify_mode, nil)
    assert_equal :operate, result[:mode]
    assert_equal :low, result[:confidence]
  end
  
  # ─────────────────────────────────────────────────────────────────────────────
  # Case Insensitivity
  # ─────────────────────────────────────────────────────────────────────────────
  
  test "classification is case insensitive" do
    result = @controller.send(:quick_classify_mode, "CREATE A LANDING PAGE")
    assert_equal :create, result[:mode]
    
    result = @controller.send(:quick_classify_mode, "What's The WEATHER?")
    assert_equal :personal, result[:mode]
    
    result = @controller.send(:quick_classify_mode, "BRAINSTORM IDEAS")
    assert_equal :ideate, result[:mode]
  end
end
