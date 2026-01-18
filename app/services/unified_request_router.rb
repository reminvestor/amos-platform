# frozen_string_literal: true

# UnifiedRequestRouter - Combined model + canvas routing in one decision
#
# DUAL ROUTING SYSTEM:
# 1. Quick regex pass (~5ms) - handles 70-80% of cases
# 2. If ambiguous → cheap LLM classifier (Nemotron Nano 2 or DeepSeek V3)
#    Returns: model, canvas, reasoning in ONE call
#
# OPEN SOURCE ONLY:
# - Nemotron Nano 2: $0.06/$0.23 per 1M tokens (classifier)
# - DeepSeek V3: $0.58/$1.68 (general/coding)
# - DeepSeek R1: $1.35/$5.40 (reasoning)
# - Mistral Large 3: $0.50/$1.50 (tool execution)
# - Qwen3 32B: $0.15/$0.60 (cheap tools)
#
# NO ANTHROPIC MODELS IN ROUTING!
#
class UnifiedRequestRouter
  # Task categories for routing
  TASK_CATEGORIES = {
    tools: {
      model: 'mistral-large-3',
      description: 'Needs tool execution (CRUD, integrations, data fetching)'
    },
    reasoning: {
      model: 'deepseek-r1',
      description: 'Complex analysis, strategy, planning, GTM'
    },
    coding: {
      model: 'deepseek-v3',
      description: 'Code generation, HTML/CSS/JS, technical'
    },
    general: {
      model: 'deepseek-v3',
      description: 'Conversation, questions, simple tasks'
    },
    simple: {
      model: 'nemotron-nano',
      description: 'Very simple queries, classifications'
    }
  }.freeze

  # Canvas types with patterns
  CANVAS_PATTERNS = {
    dashboard: /\b(dashboard|overview|summary|home)\b/i,
    campaign_viewer: /\b(campaign|email campaign)s?\b/i,
    contact_viewer: /\b(contact|lead|subscriber)s?\b/i,
    landing_page_viewer: /\b(landing page|lp)s?\b/i,
    document_viewer: /\b(document|file|upload|pdf)s?\b/i,
    analytics: /\b(analytics?|performance|metrics?|report)\b/i,
    module_manager: /\b(module|app|custom app)s?\b/i,
    scheduled_tasks: /\b(schedule|scheduled|task|automation)s?\b/i,
    work_items: /\b(work item|inbox|notification)s?\b/i,
    integrations_manager: /\b(integration|connection)s?\b/i,
  }.freeze

  # ═══════════════════════════════════════════════════════════════
  # REGEX PATTERNS - Quick detection (Phase 1)
  # ═══════════════════════════════════════════════════════════════

  # OBVIOUS tool patterns - very high confidence
  TOOL_PATTERNS = [
    /\b(create|add|new)\s+(a\s+)?(contact|task|landing\s*page|campaign|module)\b/i,
    /\b(send|compose)\s+(an?\s+)?email\s+to\b/i,
    /\b(delete|remove)\s+(the\s+|my\s+)?(contact|task|campaign)\b/i,
    /\b(show|list|get)\s+(me\s+)?(my|all)\s+(contacts?|tasks?|campaigns?|customers?)\b/i,
    /\b(connect|sync)\s+(to|with)\s+(stripe|shopify|hubspot)\b/i,
    /\bget\s+(my\s+)?stripe\s+(customers?|data)\b/i,
    /\bhttps?:\/\/\S+/i,
  ].freeze

  # OBVIOUS reasoning patterns
  REASONING_PATTERNS = [
    /\b(analyze|analysis|evaluate|assessment)\b/i,
    /\b(strategy|strategic|plan|planning|roadmap)\b/i,
    /\b(pros?\s+and\s+cons?|trade-?offs?|weigh)\b/i,
    /\b(compare|contrast|versus|vs\.?)\s+.+/i,
    /\b(recommend|suggestion|advice)\s+(for|on|about)\b/i,
    /\b(gtm|go.to.market|business\s+plan)\b/i,
    /\b(optimize|optimization|improve\s+my)\b/i,
  ].freeze

  # OBVIOUS coding patterns
  CODING_PATTERNS = [
    /\b(code|coding|program|script|function)\b/i,
    /\b(python|javascript|ruby|typescript|html|css)\b/i,
    /\b(generate|create)\s+.*(html|css|js|code)\b/i,
    /```/,
  ].freeze

  # NO action needed - simple conversation
  SIMPLE_PATTERNS = [
    /^(hi|hello|hey|thanks|ok|yes|no)\b/i,
    /^how are you/i,
    /^what('?s| is| are)\s+(your|the)\s+(name|weather)/i,
    /\b(thanks|thank you|bye|goodbye)\b/i,
  ].freeze

  attr_reader :entity, :user, :bedrock_service

  def initialize(entity: nil, user: nil)
    @entity = entity
    @user = user
    @bedrock_service = BedrockService.new(entity)
  end

  # ═══════════════════════════════════════════════════════════════
  # MAIN ENTRY POINT
  # ═══════════════════════════════════════════════════════════════
  
  # Returns: { model:, canvas:, needs_tools:, task_type:, reasoning:, latency_ms: }
  def route(message:, context: {})
    start_time = Time.current

    # Phase 1: Quick regex detection
    regex_result = regex_classify(message, context)
    
    if regex_result[:confident]
      return finalize_result(regex_result, start_time, method: :regex)
    end

    # Phase 2: LLM classification for ambiguous cases (use cheap model)
    llm_result = llm_classify(message, context)
    finalize_result(llm_result, start_time, method: :llm)
  end

  # Async version for parallel execution
  def route_async(message:, context: {})
    Thread.new { route(message: message, context: context) }
  end

  private

  # ═══════════════════════════════════════════════════════════════
  # PHASE 1: REGEX CLASSIFICATION
  # ═══════════════════════════════════════════════════════════════

  def regex_classify(message, context)
    # Check for follow-up confirmations first
    if confirmation?(message, context)
      return {
        confident: true,
        task_type: :tools,
        model: 'mistral-large-3',
        needs_tools: true,
        canvas: detect_canvas(message),
        reasoning: 'Follow-up confirmation to tool action'
      }
    end

    # Simple greetings/thanks
    if SIMPLE_PATTERNS.any? { |p| message.match?(p) }
      return {
        confident: true,
        task_type: :simple,
        model: 'deepseek-v3',  # Use DeepSeek even for simple - it's fast and will handoff if needed
        needs_tools: false,
        canvas: :keep_current,
        reasoning: 'Simple greeting/acknowledgment'
      }
    end

    # Obvious tool needs
    if TOOL_PATTERNS.any? { |p| message.match?(p) }
      return {
        confident: true,
        task_type: :tools,
        model: 'mistral-large-3',
        needs_tools: true,
        canvas: detect_canvas(message),
        reasoning: 'Obvious tool pattern detected'
      }
    end

    # Obvious reasoning
    if REASONING_PATTERNS.any? { |p| message.match?(p) }
      return {
        confident: true,
        task_type: :reasoning,
        model: 'deepseek-r1',
        needs_tools: false,
        canvas: detect_canvas(message),
        reasoning: 'Analysis/strategy/planning detected'
      }
    end

    # Obvious coding
    if CODING_PATTERNS.any? { |p| message.match?(p) }
      return {
        confident: true,
        task_type: :coding,
        model: 'deepseek-v3',
        needs_tools: false,
        canvas: detect_canvas(message),
        reasoning: 'Code generation task detected'
      }
    end

    # Not confident - need LLM classification
    {
      confident: false,
      task_type: :general,
      model: 'deepseek-v3',
      needs_tools: false,
      canvas: detect_canvas(message),
      reasoning: 'Ambiguous - will use LLM classifier'
    }
  end

  def confirmation?(message, context)
    return false unless context[:recent_messages].present?
    return false unless message.strip.split.length <= 10

    confirmation_words = %w[yes yeah yep sure ok okay do\ it go\ ahead please]
    is_confirmation = confirmation_words.any? { |w| message.downcase.start_with?(w) }
    
    return false unless is_confirmation

    # Check if last assistant message offered an action
    last_assistant = context[:recent_messages].reverse.find { |m| m[:role] == 'assistant' }
    return false unless last_assistant

    offer_patterns = [
      /would you like me to/i,
      /should i/i,
      /do you want me to/i,
      /shall i/i,
      /i can (create|save|send|import|export|fetch)/i,
    ]

    offer_patterns.any? { |p| last_assistant[:content].to_s.match?(p) }
  end

  def detect_canvas(message)
    CANVAS_PATTERNS.each do |canvas, pattern|
      return canvas if message.match?(pattern)
    end
    :keep_current
  end

  # ═══════════════════════════════════════════════════════════════
  # PHASE 2: LLM CLASSIFICATION (Nemotron Nano 2 - cheapest)
  # ═══════════════════════════════════════════════════════════════

  def llm_classify(message, context)
    prompt = build_classifier_prompt(message)
    
    begin
      # Use Nemotron Nano 2 - cheapest model ($0.06/$0.23 per 1M tokens)
      response = @bedrock_service.send_message_converse(
        prompt,
        model: 'nemotron-nano',
        max_tokens: 100,
        temperature: 0.1
      )

      parse_classifier_response(response, message)
    rescue => e
      Rails.logger.warn "[UnifiedRouter] LLM classification failed: #{e.message}"
      # Default to DeepSeek V3 - it will handoff to Mistral if tools needed
      {
        confident: true,
        task_type: :general,
        model: 'deepseek-v3',
        needs_tools: false,
        canvas: detect_canvas(message),
        reasoning: 'LLM classification failed - defaulting to DeepSeek'
      }
    end
  end

  def build_classifier_prompt(message)
    <<~PROMPT
      Classify this user request. Output JSON only:

      {"task_type": "tools|reasoning|coding|general", "canvas": "dashboard|contact_viewer|landing_page_viewer|campaign_viewer|analytics|module_manager|keep_current", "needs_tools": true|false}

      Task types:
      - tools: needs API calls, CRUD operations, data fetching, integrations
      - reasoning: analysis, strategy, planning, pros/cons, recommendations
      - coding: code generation, HTML/CSS/JS, technical implementation
      - general: conversation, questions, explanations

      User message: "#{message.truncate(500)}"

      JSON:
    PROMPT
  end

  def parse_classifier_response(response, message)
    # Try to parse JSON from response
    json_match = response.to_s.match(/\{[^}]+\}/)
    
    if json_match
      parsed = JSON.parse(json_match[0])
      task_type = parsed['task_type']&.to_sym || :general
      canvas = parsed['canvas']&.to_sym || :keep_current
      needs_tools = parsed['needs_tools'] == true

      model = case task_type
              when :tools then 'mistral-large-3'
              when :reasoning then 'deepseek-r1'
              when :coding then 'deepseek-v3'
              else 'deepseek-v3'
              end

      {
        confident: true,
        task_type: task_type,
        model: model,
        needs_tools: needs_tools,
        canvas: canvas,
        reasoning: "LLM classified as #{task_type}"
      }
    else
      # Couldn't parse - default to DeepSeek
      {
        confident: true,
        task_type: :general,
        model: 'deepseek-v3',
        needs_tools: false,
        canvas: detect_canvas(message),
        reasoning: 'LLM response unclear - defaulting to DeepSeek'
      }
    end
  rescue JSON::ParserError
    {
      confident: true,
      task_type: :general,
      model: 'deepseek-v3',
      needs_tools: false,
      canvas: detect_canvas(message),
      reasoning: 'JSON parse error - defaulting to DeepSeek'
    }
  end

  def finalize_result(result, start_time, method:)
    result.merge(
      latency_ms: ((Time.current - start_time) * 1000).round,
      detection_method: method
    )
  end
end

