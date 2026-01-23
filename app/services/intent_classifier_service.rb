# frozen_string_literal: true

# IntentClassifierService - Smart intent detection for seamless mode adaptation
#
# FOUR PRIMARY MODES (Amos's role adapts, identity stays constant):
#   1. PERSONAL  - Non-work topics, life admin, casual conversation
#   2. IDEATE    - Brainstorming, exploring ideas, getting suggestions (NO actions)
#   3. OPERATE   - Business operations, data queries, executing tasks
#   4. CREATE    - Building something - delegate to specialist agents
#
# Uses fast regex patterns first, LLM fallback for ambiguous messages.
#
# Usage:
#   classifier = IntentClassifierService.new(entity: entity)
#   
#   # Primary mode classification (fast path)
#   mode = classifier.classify_mode(message: "brainstorm some ideas for my landing page")
#   # => :ideate
#   
#   # Full classification with all details
#   result = classifier.classify(message: "show it", conversation_history: [...], needs: [:mode, :canvas])
#   result[:mode]           # :personal, :ideate, :operate, :create
#   result[:canvas]         # 'automation_dashboard' or nil
#   result[:design_intent]  # :module, :app, :landing_page, etc. (when mode is :create)
#
class IntentClassifierService
  # ═══════════════════════════════════════════════════════════════════════════
  # PRIMARY MODES - Amos's role adapts seamlessly based on these
  # ═══════════════════════════════════════════════════════════════════════════
  
  PRIMARY_MODES = %i[personal ideate operate create].freeze
  
  # PERSONAL mode patterns - non-work, life admin, casual
  PERSONAL_PATTERNS = [
    /\b(personal|my\s+life|life\s+admin|not\s+work|off\s+work)\b/i,
    /\b(remind\s+me\s+to|don't\s+forget|remember\s+to)\s+(pick\s+up|call\s+mom|buy|get|grab)/i,
    /\b(what('?s| is)\s+(the\s+)?(weather|time|date|news))\b/i,
    /\b(recipe|cooking|dinner|lunch|breakfast)\s+(for|ideas?|suggestion)/i,
    /\b(weekend|vacation|holiday|birthday|anniversary)\s+(plans?|ideas?)/i,
    /\b(how\s+are\s+you|what'?s\s+up|hey\s+amos|hi\s+amos|hello)\b/i,
    /\b(tell\s+me\s+a\s+(joke|story)|entertain\s+me)\b/i,
    /\b(recommend\s+a\s+(movie|book|restaurant|show|song))\b/i,
    /\b(help\s+me\s+(relax|unwind|de-?stress))\b/i,
    /\b(my\s+(kids?|family|spouse|partner|dog|cat|pet))\b/i,
    /\b(grocery|shopping)\s+list\b/i,
    /\b(workout|exercise|gym|fitness)\s+(plan|routine|ideas?)/i
  ].freeze
  
  # IDEATE mode patterns - brainstorming, exploring, getting ideas (NO actions)
  IDEATE_PATTERNS = [
    /\b(brainstorm|ideate|explore\s+ideas?|think\s+about)\b/i,
    /\b(what\s+do\s+you\s+think\s+(about|of))\b/i,
    /\b(give\s+me\s+(some\s+)?ideas?\s+(for|about|on))\b/i,
    /\b(suggest|recommendation|what\s+(would|could|should)\s+(you|we|i))\b/i,
    /\b(help\s+me\s+(think|figure\s+out|decide|explore))\b/i,
    /\b(what\s+are\s+(some|the)\s+(options?|possibilities|ways))\b/i,
    /\b(how\s+(might|could|would)\s+(we|i|you))\b/i,
    /\b(let'?s\s+(discuss|talk\s+about|explore|think\s+through))\b/i,
    /\b(i'?m\s+(thinking\s+about|considering|wondering))\b/i,
    /\b(what\s+if\s+we|hypothetically|in\s+theory)\b/i,
    /\b(pros?\s+and\s+cons?|trade-?offs?|compare\s+options?)\b/i,
    /\b(feedback\s+on|thoughts?\s+on|opinion\s+on)\b/i,
    /\b(is\s+it\s+a\s+good\s+idea|should\s+i|would\s+it\s+be\s+better)\b/i,
    /\b(explore|evaluate|assess|analyze)\s+(the\s+)?(idea|concept|approach)/i
  ].freeze
  
  # CREATE mode patterns - user wants something BUILT (delegate to agents)
  CREATE_PATTERNS = [
    /\b(create|build|make|design|generate|set\s+up)\s+(me\s+)?(a|an|the|my)\s/i,
    /\b(i\s+need|i\s+want|we\s+need)\s+(a|an)\s+(new\s+)?(landing\s*page|email|workflow|app|module|automation)/i,
    /\b(new\s+)(landing\s*page|email\s*(template|campaign)?|workflow|automation|app|module)/i,
    /\b(build|create|design)\s+(this|it|one)\s+(for\s+me)?/i,
    /\b(start|begin)\s+(building|creating|designing|working\s+on)/i,
    /\b(put\s+together|draft|write)\s+(a|an)\s+(landing\s*page|email|campaign)/i,
    /\blet'?s\s+(build|create|make|design)\b/i,
    /\b(spin\s+up|whip\s+up|throw\s+together)\s+(a|an)\b/i,
    /\b(automate|automation\s+for|workflow\s+for)\b/i
  ].freeze
  
  # CREATE target objects - what are they building?
  CREATE_TARGETS = {
    landing_page: /\b(landing\s*page|website|web\s*page|sales\s*page|squeeze\s*page)\b/i,
    email: /\b(email|newsletter|email\s*campaign|email\s*sequence|drip)\b/i,
    workflow: /\b(workflow|automation|trigger|automated?\s*task|sequence)\b/i,
    module: /\b(module|tracker|custom\s*app|system|database|form)\b/i,
    app: /\b(app|application|web\s*app|software|platform)\b/i,
    integration: /\b(integration|connect|api|webhook)\b/i,
    agent: /\b(agent|assistant|bot|ai\s*helper)\b/i
  }.freeze

  # ═══════════════════════════════════════════════════════════════════════════
  # CANVAS & OTHER CLASSIFICATION (kept for backward compatibility)
  # ═══════════════════════════════════════════════════════════════════════════
  
  # Available canvases for classification
  AVAILABLE_CANVASES = %w[
    dashboard campaign_viewer contact_viewer landing_page_viewer document_viewer
    analytics module_manager scheduled_tasks work_items integrations_manager
    automation_dashboard workflow_designer design_preview component_gallery
    application_plan_preview landing_page_editor freeform keep_current
  ].freeze

  # Thinking depth options
  THINKING_DEPTHS = %w[light medium deep].freeze

  # Design intent types - what does the user want to CREATE?
  DESIGN_INTENTS = %w[module app landing_page email workflow integration agent none].freeze

  attr_reader :entity

  def initialize(entity:)
    @entity = entity
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PRIMARY MODE CLASSIFICATION - Fast path for seamless role adaptation
  # ═══════════════════════════════════════════════════════════════════════════
  
  # Classify the primary mode - this is the main entry point for role adaptation
  # @param message [String] Current user message
  # @param conversation_history [Array] Recent messages for context (optional)
  # @return [Hash] { mode: :personal/:ideate/:operate/:create, create_target: :landing_page/etc, confidence: :high/:medium }
  def classify_mode(message:, conversation_history: [])
    return { mode: :operate, confidence: :low } if message.blank?
    
    # FAST PATH: Regex-based detection (< 1ms)
    result = regex_classify_mode(message)
    
    if result[:confidence] == :high
      Rails.logger.info "[IntentClassifier] Mode: #{result[:mode]} (regex, high confidence)"
      return result
    end
    
    # MEDIUM CONFIDENCE: Return regex result but could use LLM for ambiguous cases
    if result[:confidence] == :medium
      Rails.logger.info "[IntentClassifier] Mode: #{result[:mode]} (regex, medium confidence)"
      return result
    end
    
    # LOW CONFIDENCE: Try LLM classification for truly ambiguous messages
    if conversation_history.present? || ambiguous_message?(message)
      llm_result = llm_classify_mode(message, conversation_history)
      if llm_result[:confidence] != :low
        Rails.logger.info "[IntentClassifier] Mode: #{llm_result[:mode]} (LLM, #{llm_result[:confidence]} confidence)"
        return llm_result
      end
    end
    
    # Default to operate
    Rails.logger.info "[IntentClassifier] Mode: :operate (default)"
    { mode: :operate, confidence: :low }
  end
  
  # Fast regex-based mode classification
  def regex_classify_mode(message)
    msg = message.to_s.strip
    
    # Check PERSONAL patterns first (most specific)
    if PERSONAL_PATTERNS.any? { |p| msg.match?(p) }
      return { mode: :personal, confidence: :high }
    end
    
    # Check CREATE patterns (explicit build/create requests)
    if CREATE_PATTERNS.any? { |p| msg.match?(p) }
      target = detect_create_target(msg)
      return { mode: :create, create_target: target, confidence: :high }
    end
    
    # Check IDEATE patterns (brainstorming, exploring ideas)
    if IDEATE_PATTERNS.any? { |p| msg.match?(p) }
      # But if they ALSO mention a create target with action verbs, it's CREATE
      if msg.match?(/\b(for|to)\s+(build|create|make|design)\b/i) && detect_create_target(msg)
        target = detect_create_target(msg)
        return { mode: :create, create_target: target, confidence: :medium }
      end
      return { mode: :ideate, confidence: :high }
    end
    
    # Check for implicit create (mentions target without explicit create verb)
    # e.g., "I need a landing page" without "create"
    if msg.match?(/\b(i\s+need|i\s+want|we\s+need|we\s+want|get\s+me)\b/i)
      target = detect_create_target(msg)
      if target
        return { mode: :create, create_target: target, confidence: :medium }
      end
    end
    
    # Default: OPERATE (business operations)
    { mode: :operate, confidence: :medium }
  end
  
  # Detect what the user wants to create
  def detect_create_target(message)
    CREATE_TARGETS.each do |target, pattern|
      return target if message.match?(pattern)
    end
    nil
  end
  
  # Check if message is ambiguous (needs LLM)
  def ambiguous_message?(message)
    msg = message.downcase
    # Very short messages
    return true if msg.split.length < 3
    # Pronouns without context
    return true if msg.match?(/\b(it|this|that|these|those)\b/) && !msg.match?(/\b(show|display|view)\b/)
    # Questions without clear intent
    return true if msg.match?(/^(can|could|would|should|what|how)\b/) && !IDEATE_PATTERNS.any? { |p| msg.match?(p) }
    false
  end
  
  # LLM-based mode classification for ambiguous messages
  def llm_classify_mode(message, conversation_history)
    prompt = build_mode_classification_prompt(message, conversation_history)
    
    begin
      response = call_llm(prompt)
      parse_mode_response(response)
    rescue => e
      Rails.logger.warn "[IntentClassifier] LLM mode classification failed: #{e.message}"
      { mode: :operate, confidence: :low }
    end
  end
  
  def build_mode_classification_prompt(message, history)
    context = format_conversation_context(history)
    
    <<~PROMPT
      You are classifying user intent into one of four modes. Respond with ONLY the mode name.

      MODES:
      - PERSONAL: Non-work topics, personal life, casual chat, jokes, recommendations, reminders about personal things
      - IDEATE: User wants to BRAINSTORM or DISCUSS ideas. They're exploring, not ready to build yet. Key phrases: "what do you think", "give me ideas", "suggest", "explore options"
      - OPERATE: User wants to DO something operational - query data, view things, manage contacts, run reports, execute tasks
      - CREATE: User wants something BUILT - a landing page, email, workflow, app, module. They're ready to have it made.

      CRITICAL DISTINCTION:
      - "What do you think about building a landing page?" → IDEATE (discussing the idea)
      - "Build me a landing page" → CREATE (ready to build)
      - "Show me my landing pages" → OPERATE (viewing existing things)
      - "What should I have for dinner?" → PERSONAL (non-work)

      CONVERSATION CONTEXT:
      #{context}

      CURRENT MESSAGE: "#{message.truncate(300)}"

      Respond with ONLY one word: PERSONAL, IDEATE, OPERATE, or CREATE
    PROMPT
  end
  
  def parse_mode_response(response)
    mode_str = response.to_s.strip.upcase.gsub(/[^A-Z]/, '')
    
    mode = case mode_str
           when 'PERSONAL' then :personal
           when 'IDEATE' then :ideate
           when 'CREATE' then :create
           else :operate
           end
    
    { mode: mode, confidence: :medium, source: :llm }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # LEGACY CLASSIFICATION METHODS (backward compatibility)
  # ═══════════════════════════════════════════════════════════════════════════

  # Main classification entry point
  # @param message [String] Current user message
  # @param conversation_history [Array] Recent messages for context
  # @param needs [Array<Symbol>] What to classify (:canvas, :thinking_depth, :context_topic, :mode)
  # @return [Hash] Classification results
  def classify(message:, conversation_history: [], needs: [:canvas, :thinking_depth])
    return {} if needs.empty?
    
    result = {}
    
    # Handle mode classification separately (fast path)
    if needs.include?(:mode)
      mode_result = classify_mode(message: message, conversation_history: conversation_history)
      result.merge!(mode_result)
      needs = needs - [:mode]
    end
    
    return result if needs.empty?

    prompt = build_classification_prompt(message, conversation_history, needs)
    
    begin
      response = call_llm(prompt)
      result.merge!(parse_response(response, needs))
    rescue => e
      Rails.logger.warn "[IntentClassifier] LLM classification failed: #{e.message}"
      result.merge!(default_response(needs))
    end
    
    result
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

    if needs.include?(:design_intent)
      prompt_parts << "DESIGN: <one of: #{DESIGN_INTENTS.join(', ')}>"
      prompt_parts << "  - 'module' if user wants to CREATE/BUILD/DESIGN a module, system, tracker, custom app"
      prompt_parts << "  - 'app' if user wants to CREATE a full application or web app"
      prompt_parts << "  - 'landing_page' if user wants to CREATE/BUILD a landing page or website page"
      prompt_parts << "  - 'email' if user wants to CREATE/BUILD an email campaign or sequence"
      prompt_parts << "  - 'workflow' if user wants to CREATE/BUILD an automation or workflow"
      prompt_parts << "  - 'integration' if user wants to SET UP a new API integration"
      prompt_parts << "  - 'agent' if user wants to CREATE a new AI agent"
      prompt_parts << "  - 'none' if user is NOT asking to CREATE something (just querying, viewing, chatting)"
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

      if needs.include?(:design_intent) && line.match?(/^DESIGN:\s*/i)
        intent = line.sub(/^DESIGN:\s*/i, '').strip.downcase.gsub(/[^a-z_]/, '')
        result[:design_intent] = intent.to_sym if DESIGN_INTENTS.include?(intent) && intent != 'none'
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
    result[:design_intent] = nil if needs.include?(:design_intent)
    result
  end

  # Convenience method for design intent classification
  def classify_design_intent(message:, conversation_history: [])
    result = classify(message: message, conversation_history: conversation_history, needs: [:design_intent])
    result[:design_intent]
  end
end

