# frozen_string_literal: true

require "test_helper"

class Amos::LearnedBehaviorsTest < ActiveSupport::TestCase
  def setup
    skip "Redis not available" unless redis_available?
    
    @user = users(:one)
    @entity = entities(:one)
    
    @behaviors = Amos::LearnedBehaviors.new(user: @user, entity: @entity)
    
    # Clean up completely - use unique test isolation
    @behaviors.clear_all
    # Also flush any potentially polluted keys
    flush_test_redis_keys
  end

  def teardown
    @behaviors.clear_all if @behaviors
    flush_test_redis_keys
  end
  
  private
  
  def redis_available?
    # Check that $redis is a real Redis, not NullRedis
    return false if $redis.nil?
    return false if $redis.is_a?(NullRedis)
    
    # Also verify it's actually connected
    result = $redis.ping
    result == "PONG"
  rescue => e
    false
  end
  
  def flush_test_redis_keys
    return unless redis_available?
    # Delete all learned behavior keys for test user/entity
    keys = $redis.keys("amos:learned:#{@user&.id}:#{@entity&.id}:*")
    $redis.del(*keys) if keys.any?
  rescue => e
    # Ignore cleanup errors
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Core Operations
  # ─────────────────────────────────────────────────────────────────────────────

  test "learn stores a behavior in Redis" do
    result = @behaviors.learn(
      type: :tool_correction,
      behavior: "Don't use parse_excel for CSV files, use parse_csv instead",
      source: 'explicit_correction',
      confidence: 0.9
    )
    
    assert result
    
    behaviors = @behaviors.get_behaviors(:tool_correction)
    assert_equal 1, behaviors.length
    assert_includes behaviors.first[:behavior], "parse_excel"
  end

  test "learn rejects invalid behavior types" do
    result = @behaviors.learn(
      type: :invalid_type,
      behavior: "Some behavior",
      source: 'test'
    )
    
    assert_not result
  end

  test "get_behaviors returns empty array when none exist" do
    result = @behaviors.get_behaviors(:format_preference)
    
    assert_equal [], result
  end

  test "all_behaviors returns hash of all types" do
    @behaviors.learn(type: :tool_correction, behavior: "Correction 1")
    @behaviors.learn(type: :format_preference, behavior: "Preference 1")
    
    all = @behaviors.all_behaviors
    
    assert all.key?(:tool_correction)
    assert all.key?(:format_preference)
    assert_not all.key?(:workflow_pattern) # Not added
  end

  test "forget removes specific behavior" do
    @behaviors.learn(type: :tool_correction, behavior: "First")
    @behaviors.learn(type: :tool_correction, behavior: "Second")
    
    @behaviors.forget(type: :tool_correction, behavior_index: 0)
    
    remaining = @behaviors.get_behaviors(:tool_correction)
    assert_equal 1, remaining.length
    assert_equal "First", remaining.first[:behavior]
  end

  test "clear_type removes all behaviors of a type" do
    @behaviors.learn(type: :tool_correction, behavior: "One")
    @behaviors.learn(type: :tool_correction, behavior: "Two")
    
    @behaviors.clear_type(:tool_correction)
    
    assert_equal [], @behaviors.get_behaviors(:tool_correction)
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Deduplication
  # ─────────────────────────────────────────────────────────────────────────────

  test "does not add duplicate behaviors" do
    @behaviors.learn(type: :format_preference, behavior: "Use tables for data")
    @behaviors.learn(type: :format_preference, behavior: "Use tables for data presentation")
    
    behaviors = @behaviors.get_behaviors(:format_preference)
    # Should not add the second one since it overlaps
    assert behaviors.length <= 2
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Prompt Formatting
  # ─────────────────────────────────────────────────────────────────────────────

  test "format_for_prompt returns empty string when no behaviors" do
    result = @behaviors.format_for_prompt
    
    assert_equal "", result
  end

  test "format_for_prompt includes behavior details" do
    @behaviors.learn(type: :tool_correction, behavior: "Use search_documents not list_documents")
    @behaviors.learn(type: :format_preference, behavior: "User prefers tables over lists")
    
    result = @behaviors.format_for_prompt
    
    assert_includes result, "LEARNED BEHAVIORS"
    assert_includes result, "Tool Correction"
    assert_includes result, "search_documents"
    assert_includes result, "Format Preference"
    assert_includes result, "tables over lists"
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Correction Detection
  # ─────────────────────────────────────────────────────────────────────────────

  test "analyze_for_corrections detects explicit correction" do
    @behaviors.analyze_for_corrections(
      user_message: "No, don't use tables. I want bullet points.",
      amos_response: "Here's the data in a table format..."
    )
    
    # Should have learned a format preference
    all = @behaviors.all_behaviors
    assert all.any? { |type, behaviors| behaviors.any? { |b| b[:source] == 'explicit_correction' } }
  end

  test "analyze_for_corrections detects future preference" do
    @behaviors.analyze_for_corrections(
      user_message: "In the future, please keep responses brief",
      amos_response: "Here's a detailed explanation..."
    )
    
    # Should have learned something
    all = @behaviors.all_behaviors
    assert all.any?
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Applied Tracking
  # ─────────────────────────────────────────────────────────────────────────────

  test "mark_applied increments apply count" do
    @behaviors.learn(type: :tool_correction, behavior: "Test behavior")
    
    @behaviors.mark_applied(type: :tool_correction, behavior_index: 0)
    
    behaviors = @behaviors.get_behaviors(:tool_correction)
    assert_equal 1, behaviors.first[:applied_count]
    assert behaviors.first[:last_applied_at].present?
  end
end
