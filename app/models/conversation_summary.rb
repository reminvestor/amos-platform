# ConversationSummary
#
# Stores AI-generated summaries of older conversation segments.
# This allows Scout to maintain context over long conversations without
# exceeding token limits on the active context window.
#
# Flow:
# 1. When conversation exceeds threshold (e.g., 30 messages), trigger summarization
# 2. Summarize messages 1-20, keep messages 21-30 in active window
# 3. Store summary with key topics, decisions, and action items
# 4. Load summary into system prompt for context continuity
#
class ConversationSummary < ApplicationRecord
  belongs_to :user
  belongs_to :entity

  validates :session_id, presence: true
  validates :summary, presence: true
  validates :message_start_index, presence: true, numericality: { greater_than: 0 }
  validates :message_end_index, presence: true, numericality: { greater_than: 0 }
  validates :messages_summarized, presence: true, numericality: { greater_than: 0 }

  scope :active, -> { where(active: true) }
  scope :for_session, ->(session_id) { where(session_id: session_id) }
  scope :by_recency, -> { order(message_end_index: :desc) }

  # Get all active summaries for a session, formatted for prompt inclusion
  def self.for_prompt(session_id:, limit: 3)
    summaries = active.for_session(session_id).by_recency.limit(limit)
    return "" if summaries.empty?

    formatted = summaries.reverse.map.with_index do |summary, idx|
      segment_label = if summaries.count == 1
        "Earlier in this conversation"
      else
        "Conversation segment #{idx + 1}"
      end

      parts = ["📝 #{segment_label} (messages #{summary.message_start_index}-#{summary.message_end_index}):"]
      parts << summary.summary

      if summary.key_topics.present?
        topics = parse_json_array(summary.key_topics)
        parts << "Topics: #{topics.join(', ')}" if topics.any?
      end

      if summary.key_decisions.present?
        decisions = parse_json_array(summary.key_decisions)
        parts << "Decisions made: #{decisions.join('; ')}" if decisions.any?
      end

      if summary.action_items.present?
        items = parse_json_array(summary.action_items)
        parts << "Pending items: #{items.join('; ')}" if items.any?
      end

      if summary.context_for_future.present?
        parts << "Remember: #{summary.context_for_future}"
      end

      parts.join("\n")
    end

    <<~PROMPT
      ═══════════════════════════════════════════════════════════════
      📚 CONVERSATION HISTORY SUMMARY
      ═══════════════════════════════════════════════════════════════
      
      #{formatted.join("\n\n")}
      
      ⚠️ The above summarizes earlier parts of this conversation.
      Your active window shows the most recent messages.
    PROMPT
  end

  # Create a summary from a set of messages
  def self.create_from_messages(user:, entity:, session_id:, messages:, start_index:, ai_service: nil)
    return nil if messages.blank? || messages.count < 5

    # Use provided AI service or create one
    ai_service ||= BedrockService.new(user: user, entity: entity)

    # Format messages for summarization
    conversation_text = messages.map.with_index do |msg, idx|
      role = msg[:role] == 'user' ? 'User' : 'Scout'
      "#{role}: #{msg[:content]}"
    end.join("\n\n")

    # Estimate original token count (rough: 4 chars = 1 token)
    original_tokens = conversation_text.length / 4

    # Generate summary with AI
    summary_prompt = <<~PROMPT
      Analyze this conversation segment and create a concise summary for an AI assistant to maintain context.

      CONVERSATION:
      #{conversation_text}

      Create a JSON response with:
      {
        "summary": "2-3 sentence summary of what was discussed and accomplished",
        "key_topics": ["topic1", "topic2", ...],
        "key_decisions": ["decision1", "decision2", ...],
        "action_items": ["pending item1", "pending item2", ...],
        "context_for_future": "One sentence of critical context the AI should remember"
      }

      Focus on:
      - What the user wanted to accomplish
      - What was actually done or shown
      - Any preferences or corrections the user made
      - Unfinished tasks or things to follow up on

      Be concise - this will be loaded as context for future messages.
    PROMPT

    response = ai_service.send_message(
      "You are a conversation analyzer. Return only valid JSON.",
      [{ role: "user", content: summary_prompt }],
      model: "claude-haiku-4-5-20251001",
      max_tokens: 800
    )

    # Parse response
    json_match = response.match(/\{[\s\S]*\}/m)
    return nil unless json_match

    data = JSON.parse(json_match[0])
    summary_tokens = response.length / 4

    create!(
      user: user,
      entity: entity,
      session_id: session_id,
      summary: data['summary'],
      key_topics: data['key_topics'].to_json,
      key_decisions: data['key_decisions'].to_json,
      action_items: data['action_items'].to_json,
      context_for_future: data['context_for_future'],
      message_start_index: start_index,
      message_end_index: start_index + messages.count - 1,
      messages_summarized: messages.count,
      original_tokens: original_tokens,
      summary_tokens: summary_tokens,
      model_used: "claude-haiku-4-5-20251001"
    )
  rescue JSON::ParserError => e
    Rails.logger.warn "ConversationSummary JSON parse failed: #{e.message}"
    nil
  rescue => e
    Rails.logger.error "ConversationSummary creation failed: #{e.message}"
    nil
  end

  # Check if summarization is needed for a session
  def self.needs_summarization?(session_id:, threshold: 30, window_size: 20)
    total_messages = ScoutMessage.where(session_id: session_id).count
    return false if total_messages <= threshold

    # Check what's already summarized
    last_summary = active.for_session(session_id).by_recency.first
    last_summarized_index = last_summary&.message_end_index || 0

    # Need to summarize if there are more than window_size unsummarized messages
    unsummarized_count = total_messages - last_summarized_index
    unsummarized_count > threshold
  end

  # Get compression ratio (for analytics)
  def compression_ratio
    return nil unless original_tokens.present? && summary_tokens.present? && original_tokens > 0
    ((original_tokens - summary_tokens).to_f / original_tokens * 100).round(1)
  end

  private

  def self.parse_json_array(json_string)
    return [] if json_string.blank?
    JSON.parse(json_string)
  rescue JSON::ParserError
    []
  end
end
