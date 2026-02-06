# frozen_string_literal: true

require "test_helper"

class V3::ConversationCompactionServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @entity = entities(:one)
    @service = V3::ConversationCompactionService.new(user: @user, entity: @entity)
  end

  test "does not compact short conversations" do
    messages = [
      { role: "user", content: [{ text: "Hello" }] },
      { role: "assistant", content: [{ text: "Hi there!" }] }
    ]

    result = @service.compact_if_needed(messages)
    assert_equal messages, result, "Should not compact 2 messages"
  end

  test "does not compact 4 or fewer messages" do
    messages = (1..4).map do |i|
      { role: i.odd? ? "user" : "assistant", content: [{ text: "Message #{i}" }] }
    end

    result = @service.compact_if_needed(messages)
    assert_equal messages, result
  end

  test "compact reduces message count" do
    # Create a large conversation
    messages = (1..20).map do |i|
      {
        role: i.odd? ? "user" : "assistant",
        content: [{ text: "This is message number #{i} with some content to make it longer. " * 10 }]
      }
    end

    result = @service.compact(messages)

    assert result.length < messages.length,
      "Compacted (#{result.length}) should be fewer than original (#{messages.length})"
  end

  test "compact preserves recent messages" do
    messages = (1..20).map do |i|
      {
        role: i.odd? ? "user" : "assistant",
        content: [{ text: "Message #{i}" }]
      }
    end

    result = @service.compact(messages)

    # The last message should be preserved
    last_original = messages.last[:content].first[:text]
    last_compacted = result.last[:content].first[:text]
    assert_equal last_original, last_compacted, "Last message should be preserved"
  end

  test "compact starts with summary" do
    messages = (1..20).map do |i|
      {
        role: i.odd? ? "user" : "assistant",
        content: [{ text: "Message #{i}" }]
      }
    end

    result = @service.compact(messages)

    # First message should be the summary
    first_text = result.first[:content].first[:text]
    assert_match /CONVERSATION SUMMARY/i, first_text
  end

  test "COMPACTION_THRESHOLD is reasonable" do
    assert_equal 0.75, V3::ConversationCompactionService::COMPACTION_THRESHOLD
  end

  test "RECENT_KEEP_RATIO is reasonable" do
    assert_equal 0.40, V3::ConversationCompactionService::RECENT_KEEP_RATIO
  end

  test "model context windows are configured" do
    windows = V3::ConversationCompactionService::MODEL_CONTEXT_WINDOWS
    
    assert windows.key?("default")
    assert windows["default"] > 0
    assert windows.values.all? { |v| v > 0 }
  end
end
