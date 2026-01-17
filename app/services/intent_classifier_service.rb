# frozen_string_literal: true

# IntentClassifierService - LLM-based fallback for ambiguous user intents
#
# When regex-based detection fails for:
#   1. Canvas routing (what should be displayed)
#   2. Thinking depth (how deeply should AI reason)
#   3. Context-based "show" commands
#
# Uses Nemotron Nano 2 for ultra-fast, cheap classification (~100ms, $0.06/1M tokens)
#
# Usage:
#   classifier = IntentClassifierService.new(entity: entity)
#   result = classifier.classify(
#     message: "show it",
#     conversation_history: [...],
#     needs: [:canvas, :thinking_depth]
#   )
#   result[:canvas]         # 'automation_dashboard' or nil
#   result[:thinking_depth] # :deep, :medium, :light, or nil
#   result[:context_topic]  # What the conversation is about
#
class IntentClassifierService
  # Available canvases for classification
  AVAILABLE_CANVASES = %w[
    dashboard campaign_viewer contact_viewer landing_page_viewer document_viewer
    analytics module_manager scheduled_tasks work_items integrations_manager
    automation_dashboard workflow_editor design_preview component_gallery
    application_plan_preview landing_page_editor freeform keep_current
  ].freeze

  # Thinking depth options
  THINKING_DEPTHS = %w[light medium deep].freeze

  attr_reader :entity

  def initialize(entity:)
    @entity = entity
  end

  # Main classification entry point
  # @param message [String] Current user message
  # @param conversation_history [Array] Recent messages for context
  # @param needs [Array<Symbol>] What to classify (:canvas, :thinking_depth, :context_topic)
  # @return [Hash] Classification results
  def classify(message:, conversation_history: [], needs: [:canvas, :thinking_depth])
    return {} if needs.empty?

    prompt = build_classification_prompt(message, conversation_history, needs)
    
    begin
      response = call_llm(prompt)
      parse_response(response, needs)
    rescue => e
      Rails.logger.warn "[IntentClassifier] LLM classification failed: #{e.message}"
      default_response(needs)
    end
  end

  # Classify canvas only (convenience method)
  def classify_canvas(message:, conversation_history: [])
    result = classify(message: message, conversation_history: conversation_history, needs: [:canvas, :context_topic])
    result[:canvas]
  end

  # Classify thinking depth only (convenience method)
  def classify_thinking_depth(message:, conversation_history: [])
    result = classify(message: message, conversation_history: conversation_history, needs: [:thinking_depth])
    result[:thinking_depth]&.to_sym
  end

  private

  def build_classification_prompt(message, history, needs)
    # Get recent conversation context
    recent_context = format_conversation_context(history)
    
    prompt_parts = []
    prompt_parts << "You are an intent classifier. Analyze the user message and context, then respond with ONLY the requested values in the exact format shown."
    prompt_parts << ""
    prompt_parts << "RECENT CONVERSATION:"
    prompt_parts << recent_context
    prompt_parts << ""
    prompt_parts << "CURRENT MESSAGE: \"#{message.truncate(300)}\""
    prompt_parts << ""
    prompt_parts << "RESPOND WITH (one per line):"

    if needs.include?(:canvas)
      prompt_parts << "CANVAS: <one of: #{AVAILABLE_CANVASES.join(', ')}>"
      prompt_parts << "  - Use 'keep_current' if the message is a follow-up or doesn't need a new view"
      prompt_parts << "  - Use 'automation_dashboard' for automation/workflow topics"
      prompt_parts << "  - Use 'design_preview' for design/UI/web app topics"
      prompt_parts << "  - Use 'freeform' if user needs custom content displayed"
    end

    if needs.include?(:thinking_depth)
      prompt_parts << "DEPTH: <one of: light, medium, deep>"
      prompt_parts << "  - 'light' for simple questions, greetings, quick lookups"
      prompt_parts << "  - 'medium' for standard tasks, explanations, moderate complexity"
      prompt_parts << "  - 'deep' for: analysis, strategy, debugging, 'think deeply', complex problems, architecture"
    end

    if needs.include?(:context_topic)
      prompt_parts << "TOPIC: <brief topic of the conversation in 2-5 words>"
    end

    prompt_parts.join("\n")
  end

  def format_conversation_context(history)
    return "(no prior context)" if history.blank?

    # Get last 6 messages (3 exchanges)
    recent = history.last(6)
    
    recent.map do |msg|
      role = msg[:role] || msg['role'] || 'unknown'
      content = (msg[:content] || msg['content'] || '').to_s.truncate(150)
      "#{role.upcase}: #{content}"
    end.join("\n")
  end

  def call_llm(prompt)
    bedrock_service = BedrockService.new(@entity)
    
    # Use Qwen3-Next with 4k max_tokens - quick, cheap classification call
    # This is a simple routing task - doesn't need deep thinking
    # 4k is plenty for a 3-line response
    response = bedrock_service.send_message_converse(
      prompt,
      model: 'qwen3-next-80b',
      max_tokens: 4096,  # Quick 4k call - fast and cheap
      temperature: 0.1   # Low temp for deterministic classification
    )

    response.to_s.strip
  end

  def parse_response(response, needs)
    result = {}
    lines = response.to_s.strip.lines.map(&:strip)

    lines.each do |line|
      if needs.include?(:canvas) && line.match?(/^CANVAS:\s*/i)
        canvas = line.sub(/^CANVAS:\s*/i, '').strip.downcase.gsub(/[^a-z_]/, '')
        result[:canvas] = canvas if AVAILABLE_CANVASES.include?(canvas)
      end

      if needs.include?(:thinking_depth) && line.match?(/^DEPTH:\s*/i)
        depth = line.sub(/^DEPTH:\s*/i, '').strip.downcase
        result[:thinking_depth] = depth if THINKING_DEPTHS.include?(depth)
      end

      if needs.include?(:context_topic) && line.match?(/^TOPIC:\s*/i)
        result[:context_topic] = line.sub(/^TOPIC:\s*/i, '').strip.truncate(50)
      end
    end

    # Add confidence based on how many fields we got
    result[:confident] = result.keys.length >= needs.length
    result[:source] = :llm

    Rails.logger.info "[IntentClassifier] Classified: #{result.inspect}"
    result
  end

  def default_response(needs)
    result = { source: :default, confident: false }
    result[:canvas] = 'keep_current' if needs.include?(:canvas)
    result[:thinking_depth] = 'medium' if needs.include?(:thinking_depth)
    result[:context_topic] = 'unknown' if needs.include?(:context_topic)
    result
  end
end

