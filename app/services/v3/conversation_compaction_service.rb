# frozen_string_literal: true

module V3
  # ConversationCompactionService - Smart context management
  #
  # When conversation history exceeds the model's context window,
  # instead of truncating (losing information), we:
  # 1. Take the oldest messages
  # 2. Ask the LLM to summarize key facts, decisions, and state
  # 3. Replace those messages with the summary
  # 4. Continue with summary + recent messages
  #
  # This means:
  # - No information loss (facts preserved in summary)
  # - The model knows what was discussed
  # - Sessions can run indefinitely
  #
  class ConversationCompactionService
    # Compact when context exceeds this % of model's window
    COMPACTION_THRESHOLD = 0.75
    
    # Keep the most recent N% of messages untouched
    RECENT_KEEP_RATIO = 0.40
    
    # Estimated tokens per message (rough heuristic)
    TOKENS_PER_CHAR = 0.25

    # Model context windows (approximate available for messages after system prompt + tools)
    MODEL_CONTEXT_WINDOWS = {
      "claude-sonnet-4-20250514" => 150_000,
      "claude-sonnet-4-5-20250514" => 150_000,
      "anthropic.claude-opus-4-6-v1" => 150_000,
      "anthropic.claude-sonnet-4-5-v1" => 150_000,
      "anthropic.claude-sonnet-4-v1" => 150_000,
      "claude-3-haiku" => 150_000,
      "default" => 100_000
    }.freeze

    attr_reader :user, :entity, :model

    def initialize(user:, entity:, model: nil)
      @user = user
      @entity = entity
      @model = model || "default"
    end

    # Check if compaction is needed and perform it if so
    # @param messages [Array<Hash>] Conversation messages
    # @param system_prompt [String] The system prompt (to account for its size)
    # @return [Array<Hash>] Compacted messages (or original if no compaction needed)
    def compact_if_needed(messages, system_prompt: "")
      return messages if messages.length <= 4 # Too few to compact

      estimated_tokens = estimate_tokens(messages, system_prompt)
      context_window = MODEL_CONTEXT_WINDOWS[model] || MODEL_CONTEXT_WINDOWS["default"]
      threshold = context_window * COMPACTION_THRESHOLD

      if estimated_tokens > threshold
        Rails.logger.info "[V3::Compaction] Context at #{(estimated_tokens.to_f / context_window * 100).round}% " \
                          "(#{estimated_tokens}/#{context_window} tokens). Compacting..."
        compact(messages)
      else
        Rails.logger.debug "[V3::Compaction] Context at #{(estimated_tokens.to_f / context_window * 100).round}% — no compaction needed"
        messages
      end
    end

    # Force compaction regardless of size
    # @param messages [Array<Hash>] Conversation messages
    # @return [Array<Hash>] Compacted messages
    def compact(messages)
      return messages if messages.length <= 4

      # Split: old messages to summarize, recent messages to keep
      keep_count = [(messages.length * RECENT_KEEP_RATIO).ceil, 4].max
      old_messages = messages[0..-(keep_count + 1)]
      recent_messages = messages[-keep_count..]

      Rails.logger.info "[V3::Compaction] Summarizing #{old_messages.length} old messages, keeping #{recent_messages.length} recent"

      # Generate summary of old messages
      summary = generate_summary(old_messages)

      # Build compacted message list
      compacted = [
        {
          role: "user",
          content: [{ text: "[CONVERSATION SUMMARY]\n#{summary}\n[END SUMMARY - Recent messages follow]" }]
        }
      ] + recent_messages

      Rails.logger.info "[V3::Compaction] Reduced from #{messages.length} to #{compacted.length} messages"

      compacted
    end

    private

    def estimate_tokens(messages, system_prompt)
      total_chars = system_prompt.length
      
      messages.each do |msg|
        content = msg[:content] || msg["content"]
        if content.is_a?(Array)
          content.each do |block|
            if block.is_a?(Hash)
              total_chars += (block[:text] || block["text"] || "").length
              # Tool use blocks
              total_chars += (block.dig(:tool_use, :input) || block.dig("tool_use", "input") || "").to_json.length
              # Tool results
              total_chars += (block.dig(:tool_result, :content) || block.dig("tool_result", "content") || "").to_s.length
            end
          end
        elsif content.is_a?(String)
          total_chars += content.length
        end
      end

      (total_chars * TOKENS_PER_CHAR).round
    end

    def generate_summary(messages)
      # Extract text content from messages for summarization
      conversation_text = messages.map do |msg|
        role = msg[:role] || msg["role"]
        content = extract_text(msg)
        "#{role.upcase}: #{content}" if content.present?
      end.compact.join("\n\n")

      # Use the LLM to generate a summary
      begin
        ai_service = BedrockService.new(user: user, entity: entity)

        summary_prompt = <<~PROMPT
          Summarize this conversation history concisely. Preserve:
          1. Key facts and data mentioned
          2. Decisions made
          3. Actions taken (tool calls and results)
          4. Current state/status of any work in progress
          5. User preferences expressed
          
          Be factual and specific. Include IDs, names, and numbers.
          Format as bullet points. Max 500 words.
        PROMPT

        response = ai_service.send_message(
          summary_prompt,
          [{ role: "user", content: [{ text: conversation_text.truncate(50_000) }] }],
          model: "claude-3-haiku", # Use cheap/fast model for summarization
          max_tokens: 2000,
          temperature: 0.1
        )

        # Extract text from response
        if response&.dig(:content)
          response[:content].map { |b| b[:text] }.compact.join("\n")
        elsif response.is_a?(String)
          response
        else
          # Fallback: simple extraction
          simple_summary(messages)
        end
      rescue => e
        Rails.logger.warn "[V3::Compaction] LLM summary failed (#{e.message}), using simple summary"
        simple_summary(messages)
      end
    end

    def simple_summary(messages)
      # Fallback: Extract key content without LLM
      parts = []
      parts << "Previous conversation covered #{messages.length} messages."

      # Extract user messages
      user_msgs = messages.select { |m| (m[:role] || m["role"]) == "user" }
      if user_msgs.any?
        topics = user_msgs.map { |m| extract_text(m)&.truncate(100) }.compact.first(5)
        parts << "User discussed: #{topics.join('; ')}"
      end

      # Extract tool calls
      tool_calls = []
      messages.each do |msg|
        content = msg[:content] || msg["content"]
        next unless content.is_a?(Array)
        content.each do |block|
          if block.is_a?(Hash) && (block[:tool_use] || block["tool_use"])
            tu = block[:tool_use] || block["tool_use"]
            tool_calls << (tu[:name] || tu["name"])
          end
        end
      end

      if tool_calls.any?
        parts << "Tools used: #{tool_calls.uniq.join(', ')}"
      end

      parts.join("\n")
    end

    def extract_text(message)
      content = message[:content] || message["content"]
      if content.is_a?(Array)
        content.map do |block|
          if block.is_a?(Hash)
            block[:text] || block["text"]
          end
        end.compact.join(" ")
      elsif content.is_a?(String)
        content
      end
    end
  end
end
