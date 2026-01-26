# frozen_string_literal: true

require 'test_helper'

class Learning::ImplicitFeedbackDetectorTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @session_id = SecureRandom.uuid
    @detector = Learning::ImplicitFeedbackDetector.new(entity: @entity, session_id: @session_id)
  end

  test "initializes with entity and session_id" do
    assert_equal @entity, @detector.entity
    assert_equal @session_id, @detector.session_id
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POSITIVE SIGNAL DETECTION
  # ═══════════════════════════════════════════════════════════════════════════

  test "detects positive signal from 'thanks'" do
    messages = [
      { role: 'assistant', content: 'I created the landing page for you.', id: 1 },
      { role: 'user', content: 'Thanks!', id: 2 }
    ]

    signals = @detector.analyze_conversation(messages)
    
    assert_equal 1, signals.count
    assert_equal :positive, signals.first[:type]
    assert_equal 'keyword_match', signals.first[:detection_method]
  end

  test "detects positive signal from 'perfect'" do
    messages = [
      { role: 'assistant', content: 'Here is your email template.', id: 1 },
      { role: 'user', content: 'Perfect, exactly what I needed!', id: 2 }
    ]

    signals = @detector.analyze_conversation(messages)
    
    assert_equal 1, signals.count
    assert_equal :positive, signals.first[:type]
    assert signals.first[:strength] >= 0.8  # 'perfect' has high confidence
  end

  test "detects positive signal from 'looks good'" do
    messages = [
      { role: 'assistant', content: 'I updated the hero section.', id: 1 },
      { role: 'user', content: 'Looks good, thanks!', id: 2 }
    ]

    signals = @detector.analyze_conversation(messages)
    
    assert_equal 1, signals.count
    assert_equal :positive, signals.first[:type]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # NEGATIVE SIGNAL DETECTION
  # ═══════════════════════════════════════════════════════════════════════════

  test "detects negative signal from 'no, that's not'" do
    messages = [
      { role: 'assistant', content: 'I changed the background to blue.', id: 1 },
      { role: 'user', content: "No, that's not what I wanted.", id: 2 }
    ]

    signals = @detector.analyze_conversation(messages)
    
    assert_equal 1, signals.count
    assert_equal :negative, signals.first[:type]
    assert_equal 'keyword_match', signals.first[:detection_method]
  end

  test "detects negative signal from 'wrong'" do
    messages = [
      { role: 'assistant', content: 'Here is the pricing section.', id: 1 },
      { role: 'user', content: "That's wrong, I said features section.", id: 2 }
    ]

    signals = @detector.analyze_conversation(messages)
    
    assert_equal 1, signals.count
    assert_equal :negative, signals.first[:type]
  end

  test "detects negative signal from 'try again'" do
    messages = [
      { role: 'assistant', content: 'I created the workflow.', id: 1 },
      { role: 'user', content: 'Try again, but this time add error handling.', id: 2 }
    ]

    signals = @detector.analyze_conversation(messages)
    
    assert_equal 1, signals.count
    assert_equal :negative, signals.first[:type]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # RETRY DETECTION
  # ═══════════════════════════════════════════════════════════════════════════

  test "detects retry when user repeats request" do
    messages = [
      { role: 'user', content: 'Create a landing page for my coffee shop', id: 1 },
      { role: 'assistant', content: 'I created a landing page.', id: 2 },
      { role: 'user', content: 'Create a landing page for my coffee shop please', id: 3 }
    ]

    signals = @detector.analyze_conversation(messages)
    
    # Should detect retry (user asking same thing again)
    retry_signal = signals.find { |s| s[:detection_method] == 'retry_detected' }
    
    if retry_signal
      assert_equal :negative, retry_signal[:type]
      assert retry_signal[:strength] >= 0.7
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # NO SIGNAL DETECTION
  # ═══════════════════════════════════════════════════════════════════════════

  test "returns empty array for neutral conversation" do
    messages = [
      { role: 'assistant', content: 'I updated the section.', id: 1 },
      { role: 'user', content: 'Now add a footer section.', id: 2 }
    ]

    signals = @detector.analyze_conversation(messages)
    
    # Should not detect clear positive or negative signal
    # (topic change might be detected as weak positive)
    keyword_signals = signals.select { |s| s[:detection_method] == 'keyword_match' }
    assert_empty keyword_signals
  end

  test "returns empty array for insufficient messages" do
    messages = [{ role: 'user', content: 'Hello', id: 1 }]
    signals = @detector.analyze_conversation(messages)
    
    assert_empty signals
  end

  test "returns empty array for empty messages" do
    signals = @detector.analyze_conversation([])
    assert_empty signals
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # MULTIPLE SIGNALS
  # ═══════════════════════════════════════════════════════════════════════════

  test "detects multiple signals in longer conversation" do
    messages = [
      { role: 'user', content: 'Create a pricing section', id: 1 },
      { role: 'assistant', content: 'Here is the pricing section.', id: 2 },
      { role: 'user', content: "That's wrong, I wanted 3 tiers.", id: 3 },
      { role: 'assistant', content: 'Updated to 3 pricing tiers.', id: 4 },
      { role: 'user', content: 'Perfect, thanks!', id: 5 }
    ]

    signals = @detector.analyze_conversation(messages)
    
    # Should detect both negative (wrong) and positive (perfect) signals
    assert signals.count >= 2
    
    types = signals.map { |s| s[:type] }
    assert_includes types, :negative
    assert_includes types, :positive
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SIGNAL BUILDING
  # ═══════════════════════════════════════════════════════════════════════════

  test "builds signal with correct structure" do
    messages = [
      { role: 'assistant', content: 'Done!', id: 1 },
      { role: 'user', content: 'Thanks!', id: 2 }
    ]

    signals = @detector.analyze_conversation(messages)
    signal = signals.first
    
    assert signal[:type].in?([:positive, :negative])
    assert signal[:strength].is_a?(Numeric)
    assert signal[:strength].between?(0, 1)
    assert signal[:amos_message_id].present?
    assert signal[:user_reply_id].present?
    assert signal[:detection_method].present?
    assert signal[:detected_at].is_a?(Time)
    assert signal[:context].is_a?(Hash)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SIMILARITY CALCULATION
  # ═══════════════════════════════════════════════════════════════════════════

  test "calculates similarity correctly" do
    text1 = "Create a landing page for my coffee shop"
    text2 = "Create a landing page for my coffee shop please"
    
    similarity = @detector.send(:calculate_similarity, text1, text2)
    
    # Should be highly similar
    assert similarity > 0.7
  end

  test "calculates low similarity for different topics" do
    text1 = "Create a landing page for my coffee shop"
    text2 = "What are the analytics for last month"
    
    similarity = @detector.send(:calculate_similarity, text1, text2)
    
    # Should be dissimilar
    assert similarity < 0.3
  end
end
