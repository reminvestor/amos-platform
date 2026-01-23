# frozen_string_literal: true

# UnifiedPreprocessorService - Intelligent parallel preprocessing for Scout
#
# Runs 5+ parallel analysis threads to pre-compute everything Amos needs:
#   1. Canvas routing (existing CanvasRouterService)
#   2. Tool discovery (leveraging TieredDiscoveryService)
#   3. Agent pre-warming (leveraging TieredDiscoveryService)
#   4. Integration context (connected + knowledge pre-fetch)
#   5. Module context (active modules + schemas)
#
# ARCHITECTURE PRINCIPLES:
# - Regex is LOW-HANGING FRUIT only (~70% of cases)
# - Intelligence (LLM) for ambiguous cases
# - Semantic search (RAG) for dynamic discovery
# - Parallel execution for zero added latency
# - Compact context injection (~100-200 tokens)
#
# Usage:
#   preprocessor = UnifiedPreprocessorService.new(user: user, entity: entity, current_canvas: 'dashboard')
#   result = preprocessor.preprocess(message: "Show me my Stripe customers")
#
#   result[:canvas]              # 'freeform' or built-in canvas
#   result[:tools]               # Array of relevant tool names
#   result[:suggested_agents]    # Pre-warmed agents for likely delegation
#   result[:integration_context] # Knowledge about mentioned integrations
#   result[:module_context]      # Active modules and their schemas
#   result[:context_inject]      # Compact string to inject into prompt
#
class UnifiedPreprocessorService
  # Timeout for parallel threads (fail fast, use what we have)
  # Reduced from 1500ms to 1000ms - core tools are always included now, so RAG timeout is less critical
  # TieredDiscoveryService.discover_tools takes ~600-1000ms for vector similarity search
  # This still saves latency since all 5 threads run in parallel (max 1000ms vs 5*1000ms)
  # The fallback (core tools from build_tools_from_preloaded) works if timeout is hit
  THREAD_TIMEOUT_MS = 1000
  
  # Minimum tools to always include (safety net)
  MINIMUM_TOOLS = 10
  
  attr_reader :user, :entity, :current_canvas, :session_id, :conversation_history
  
  def initialize(user:, entity:, current_canvas: nil, session_id: nil, conversation_history: nil)
    @user = user
    @entity = entity
    @current_canvas = current_canvas
    @session_id = session_id
    @conversation_history = conversation_history || []
  end
  
  # ═══════════════════════════════════════════════════════════════
  # MAIN ENTRY POINT - Runs all preprocessing in parallel
  # ═══════════════════════════════════════════════════════════════
  
  def preprocess(message:, conversation_context: nil)
    start_time = Time.current
    
    # PHASE 1: Quick regex classification (instant, handles 70% of cases)
    quick_classification = quick_classify(message)
    
    # FAST PATH: Skip heavy preprocessing for simple conversational messages
    # This can save 500-1500ms for casual chat
    if simple_conversational_message?(message, quick_classification)
      Rails.logger.info "[Preprocessor] ⚡ Fast path: skipping heavy preprocessing for simple message"
      return build_fast_path_result(quick_classification, start_time)
    end
    
    # PHASE 2: Parallel preprocessing threads
    threads = launch_parallel_threads(message, quick_classification, conversation_context)
    
    # Wait for threads with timeout
    results = collect_thread_results(threads)
    
    # PHASE 3: Plugin injection selection
    # Based on canvas context, select the most relevant plugin to inject into Amos
    plugin_injection = select_plugin_for_injection(
      message: message,
      classification: quick_classification,
      canvas_result: results[:canvas]
    )
    
    # PHASE 4: Build compact context injection
    context_inject = build_context_injection(results, quick_classification)
    
    latency_ms = ((Time.current - start_time) * 1000).round
    
    # Thinking depth: prefer LLM hint from canvas router if regex didn't find anything
    llm_thinking_depth = results[:canvas][:thinking_depth]
    final_thinking_depth = if llm_thinking_depth.present?
      llm_thinking_depth
    else
      quick_classification[:thinking_depth] || :medium
    end
    
    {
      # Routing decisions
      canvas: results[:canvas][:canvas] || :keep_current,
      canvas_delegate: results[:canvas][:delegate_to_amos],
      suggested_model: quick_classification[:model] || 'qwen3-next-80b',
      suggested_thinking_depth: final_thinking_depth,
      llm_thinking_depth_hint: llm_thinking_depth,  # Pass LLM hint for ThinkingDepthService
      
      # Design intent: Does user want to CREATE something? (LLM-classified)
      # Values: :module, :app, :landing_page, :email, :workflow, :integration, :agent, or nil
      design_intent: results[:canvas][:design_intent],
      
      # Pre-discovered resources
      tools: results[:tools][:tool_names] || [],
      tool_categories: results[:tools][:categories] || [],
      suggested_agents: results[:agents][:agents] || [],
      
      # Team-first: delegation recommendations
      delegate_first: results[:agents][:delegate_first] || false,
      delegation_target: results[:agents][:top_agent],
      delegation_reason: results[:agents][:delegation_reason],
      
      # 🔌 PLUGIN INJECTION - Instead of delegating, inject plugin capabilities into Amos
      # This allows Amos to handle specialized tasks directly without the overhead of delegation
      plugin_injection: plugin_injection,
      inject_plugin: plugin_injection.present?,
      
      # Context for integrations and modules
      integration_context: results[:integrations],
      module_context: results[:modules],
      
      # Compact injection for prompt
      context_inject: context_inject,
      
      # LLM-inferred context (when regex failed)
      llm_context_topic: results[:canvas][:context_topic],
      
      # Metadata
      latency_ms: latency_ms,
      classification_method: quick_classification[:method],
      threads_completed: results[:completed_count],
      timestamp: Time.current
    }
  end
  
  private
  
  # ═══════════════════════════════════════════════════════════════
  # FAST PATH - Skip heavy preprocessing for simple messages
  # ═══════════════════════════════════════════════════════════════
  
  # Detect simple conversational messages that don't need heavy preprocessing
  # Examples: "hi", "thanks", "ok", "what do you think?", short questions
  def simple_conversational_message?(message, classification)
    return false if message.blank?
    
    msg = message.strip.downcase
    
    # Very short messages (greetings, acknowledgments)
    return true if msg.length < 20 && !msg.match?(/\b(show|create|build|get|list|search|find|open|view)\b/)
    
    # Common greetings and acknowledgments
    return true if msg.match?(/\A(hi|hello|hey|thanks?|thank you|ok|okay|sure|yes|no|nope|got it|cool|great)\b/i)
    
    # Simple questions without action words
    return true if msg.match?(/\A(what do you think|how are you|who are you|can you help)\b/i)
    
    # Unknown intent with no entity mentions = likely conversational
    if classification[:intent] == :unknown && 
       classification[:mentioned_integrations].empty? && 
       classification[:mentioned_modules].empty? &&
       classification[:mentioned_objects].empty?
      return true if msg.length < 50 && !msg.match?(/\b(show|create|build|open|website|page|browser)\b/)
    end
    
    false
  end
  
  # Build a minimal result for fast path (no thread overhead)
  def build_fast_path_result(quick_classification, start_time)
    latency_ms = ((Time.current - start_time) * 1000).round
    
    {
      canvas: :keep_current,
      canvas_delegate: false,
      suggested_model: quick_classification[:model] || 'qwen3-next-80b',
      suggested_thinking_depth: :standard, # Simple messages don't need deep thinking
      llm_thinking_depth_hint: nil,
      design_intent: nil,
      tools: [], # Will use core tools from build_tools_from_preloaded fallback
      tool_categories: [:general],
      suggested_agents: [],
      delegate_first: false,
      delegation_target: nil,
      delegation_reason: nil,
      integration_context: { connected: [], knowledge: [] },
      module_context: { active: [], mentioned: [] },
      context_inject: "",
      llm_context_topic: nil,
      latency_ms: latency_ms,
      classification_method: :fast_path,
      threads_completed: 0,
      timestamp: Time.current
    }
  end
  
  # ═══════════════════════════════════════════════════════════════
  # PHASE 1: QUICK CLASSIFICATION (Regex-based, instant)
  # ═══════════════════════════════════════════════════════════════
  
  def quick_classify(message)
    # Intent classification
    intent = classify_intent(message)
    
    # Model suggestion based on intent (now always Qwen3-Next)
    model = suggest_model(message, intent)
    
    # Thinking depth suggestion based on intent
    thinking_depth = suggest_thinking_depth(message, intent)
    
    # Extract mentioned entities
    mentioned = extract_mentions(message)
    
    {
      intent: intent,
      model: model,
      thinking_depth: thinking_depth,
      mentioned_integrations: mentioned[:integrations],
      mentioned_modules: mentioned[:modules],
      mentioned_objects: mentioned[:objects],
      confident: intent != :unknown,
      method: :regex
    }
  end
  
  # Classify user intent from message
  def classify_intent(message)
    msg = message.downcase
    
    # VIEW intent
    return :view if msg.match?(/\b(show|view|display|list|check|how\s+(are|is|many))\b/i)
    
    # CREATE intent (internal platform objects)
    return :create_data if msg.match?(/\b(create|add|new)\s+(a\s+)?(contact|campaign|task|event|note)/i)
    
    # BUILD intent (creative/design work - delegate to agent)
    return :build if msg.match?(/\b(create|build|design|make)\s+(a\s+)?(landing\s*page|email\s*campaign|newsletter|template)/i)
    
    # INTEGRATION intent
    return :integration if msg.match?(/\b(quickbooks|stripe|gmail|shopify|salesforce|hubspot)\b/i)
    return :integration if msg.match?(/\b(sync|connect|import|export)\s+(from|to|with)\b/i)
    
    # MODULE intent
    return :module if msg.match?(/\b(module|inventory|project|ticket|custom\s*app)\b/i)
    
    # REASONING intent (complex analysis)
    return :reasoning if msg.match?(/\b(analyze|analysis|strategy|plan|evaluate|compare)\b/i)
    
    :unknown
  end
  
  # Suggest model based on intent and message
  # Now always uses qwen3-next-80b - thinking depth controls reasoning level
  def suggest_model(message, intent)
    'qwen3-next-80b' # Single model, variable thinking depth
  end
  
  # Suggest thinking depth based on intent and message complexity
  # Note: This is a hint - final decision made in ScoutGenericToolsServiceV2
  def suggest_thinking_depth(message, intent)
    case intent
    when :reasoning
      :deep # Complex analysis needs deep thinking
    when :build
      :deep # Creative work benefits from deeper reasoning
    when :view
      # Simple canvas loading doesn't need deep thinking
      if message.match?(/^\s*(show|view|list)\s+(my\s+)?\w+\s*$/i)
        :standard
      else
        :standard
      end
    else
      :standard # Auto mode floor
    end
  end
  
  # Extract mentioned integrations, modules, and objects
  def extract_mentions(message)
    msg = message.downcase
    
    integrations = []
    integrations << 'quickbooks' if msg.include?('quickbooks') || msg.include?(' qb ')
    integrations << 'stripe' if msg.include?('stripe')
    integrations << 'gmail' if msg.include?('gmail') || msg.include?('email')
    integrations << 'shopify' if msg.include?('shopify')
    
    # Check connected integrations for fuzzy matches
    connected_slugs = connected_integration_slugs
    connected_slugs.each do |slug|
      integrations << slug if msg.include?(slug.gsub('_', ' ')) || msg.include?(slug)
    end
    
    modules = []
    active_module_names.each do |name, slug|
      modules << slug if msg.include?(name.downcase) || msg.include?(slug)
    end
    
    objects = []
    %w[contact campaign landing_page document task email].each do |obj|
      objects << obj if msg.include?(obj.gsub('_', ' ')) || msg.include?(obj)
    end
    
    {
      integrations: integrations.uniq,
      modules: modules.uniq,
      objects: objects.uniq
    }
  end
  
  # ═══════════════════════════════════════════════════════════════
  # PHASE 2: PARALLEL PREPROCESSING THREADS
  # ═══════════════════════════════════════════════════════════════
  
  def launch_parallel_threads(message, classification, conversation_context)
    {
      canvas: Thread.new { preload_canvas(message) },
      tools: Thread.new { preload_tools(message, classification) },
      agents: Thread.new { preload_agents(message, classification) },
      integrations: Thread.new { preload_integrations(message, classification) },
      modules: Thread.new { preload_modules(message, classification) }
    }
  end
  
  def collect_thread_results(threads)
    results = {}
    completed = 0
    
    threads.each do |key, thread|
      begin
        thread_start = Time.current
        joined = thread.join(THREAD_TIMEOUT_MS / 1000.0)
        thread_time = ((Time.current - thread_start) * 1000).round
        
        if joined
          results[key] = joined.value || default_result(key)
          completed += 1 if results[key].present?
          
          # Log tool count for debugging
          if key == :tools && results[key][:tool_names].present?
            Rails.logger.info "[Preprocessor] Tools thread returned #{results[key][:tool_names].length} tools in #{thread_time}ms"
          end
        else
          Rails.logger.warn "[Preprocessor] Thread #{key} timed out after #{THREAD_TIMEOUT_MS}ms"
          results[key] = default_result(key)
        end
      rescue => e
        Rails.logger.warn "[Preprocessor] Thread #{key} failed: #{e.message}"
        results[key] = default_result(key)
      end
    end
    
    results[:completed_count] = completed
    results
  end
  
  def default_result(key)
    case key
    when :canvas then { canvas: :keep_current, delegate_to_amos: false }
    when :tools then { tool_names: [], categories: [] }
    when :agents then { agents: [] }
    when :integrations then { connected: [], knowledge: [] }
    when :modules then { active: [], mentioned: [] }
    else {}
    end
  end
  
  # ═══════════════════════════════════════════════════════════════
  # PLUGIN INJECTION - Inject agent capabilities directly into Amos
  # ═══════════════════════════════════════════════════════════════
  
  # Select the most relevant plugin to inject based on context
  # This allows Amos to handle specialized tasks directly without delegation overhead
  def select_plugin_for_injection(message:, classification:, canvas_result:)
    # Build canvas context from the canvas result
    canvas_context = build_canvas_context_for_injection(canvas_result)
    
    # Use PluginInjectionService to select the best plugin
    injection_service = PluginInjectionService.new(user: @user, entity: @entity)
    
    injection = injection_service.select_plugin(
      canvas_context: canvas_context,
      message: message,
      intent: classification[:intent],
      classification: classification
    )
    
    if injection.present?
      Rails.logger.info "🔌 [Preprocessor] Plugin injection selected: #{injection[:plugin_name]} (#{injection[:injection_reason]})"
    end
    
    injection
  rescue => e
    Rails.logger.warn "[Preprocessor] Plugin injection failed: #{e.message}"
    nil
  end
  
  # Build canvas context hash for plugin injection
  def build_canvas_context_for_injection(canvas_result)
    return nil unless canvas_result.present?
    
    canvas_type = canvas_result[:canvas]
    return nil if canvas_type.blank? || canvas_type == :keep_current
    
    context = { type: canvas_type.to_s }
    
    # Add canvas-specific data if available
    if canvas_result[:canvas_data].present?
      context.merge!(canvas_result[:canvas_data])
    end
    
    context
  end
  
  # ═══════════════════════════════════════════════════════════════
  # INDIVIDUAL PRELOADERS
  # ═══════════════════════════════════════════════════════════════
  
  # Canvas preloading (uses existing CanvasRouterService)
  # LLM fallback enabled: adds ~100-150ms but runs in parallel with RAG threads
  # which take ~300-400ms, so net impact is zero. Benefit: context-aware routing.
  def preload_canvas(message)
    router = CanvasRouterService.new(
      entity: @entity, 
      current_canvas: @current_canvas,
      conversation_history: @conversation_history
    )
    router.route(message: message, use_llm_fallback: true) # LLM for context-aware routing
  rescue => e
    Rails.logger.warn "[Preprocessor] Canvas preload failed: #{e.message}"
    { canvas: :keep_current, delegate_to_amos: false }
  end
  
  # Tool preloading (uses existing TieredDiscoveryService)
  def preload_tools(message, classification)
    # Use TieredDiscoveryService for RAG-based discovery
    discovery = TieredDiscoveryService.new(user: @user, entity: @entity, prompt: message)
    discovered = discovery.discover_tools(prompt: message, include_core: true)
    
    # Map to tool names
    tool_names = discovered.map { |t| t[:name] }
    
    # Determine categories from discovered tools
    categories = infer_categories_from_tools(tool_names, classification)
    
    {
      tool_names: tool_names,
      categories: categories,
      count: tool_names.size
    }
  rescue => e
    Rails.logger.warn "[Preprocessor] Tool preload failed: #{e.message}"
    { tool_names: TieredDiscoveryService::CORE_TOOLS, categories: [:general] }
  end
  
  # Agent preloading (uses existing TieredDiscoveryService)
  # KEY INSIGHT: For many tasks, delegation IS the right answer
  def preload_agents(message, classification)
    # Even view requests might benefit from module agents who know the data
    
    # Determine if this is a "delegate-first" scenario
    delegate_first = should_delegate_first?(message, classification)
    
    # Use TieredDiscoveryService for RAG-based agent discovery
    discovery = TieredDiscoveryService.new(user: @user, entity: @entity, prompt: message)
    agents = discovery.discover_agents(prompt: message, limit: 5)
    
    # Also check CapabilityRegistry for integration/module agents
    if classification[:mentioned_integrations].present?
      integration_agents = find_integration_agents(classification[:mentioned_integrations])
      agents = (integration_agents + agents).uniq { |a| a[:slug] }
    end
    
    {
      agents: agents.map { |a| { slug: a[:slug], name: a[:name], score: a[:score] } },
      top_agent: agents.first,
      delegate_first: delegate_first,
      delegation_reason: delegate_first ? delegation_reason(message, classification) : nil
    }
  rescue => e
    Rails.logger.warn "[Preprocessor] Agent preload failed: #{e.message}"
    { agents: [], delegate_first: false }
  end
  
  # Determine if Amos should delegate rather than try himself
  # PRINCIPLE: Amos SHOWS and ROUTES, Agents CREATE and BUILD
  def should_delegate_first?(message, classification)
    intent = classification[:intent]
    msg = message.downcase
    
    # BUILD intent → always delegate (creative work)
    return true if intent == :build
    
    # LANDING PAGE WORK → always delegate to Landing Page Manager
    # The LPM has specialized prompts, guaranteed tool access, and better context
    landing_page_patterns = [
      # Creating landing pages
      /\b(build|design|create|generate|make)\s+(me\s+)?(a\s+)?(an?\s+)?landing\s*page/i,
      /\b(new|custom)\s+landing\s*page/i,
      # Editing landing pages (ANY edit should go to LPM)
      /\b(edit|update|change|modify|fix|adjust)\s+.{0,30}(landing\s*page|this\s+page|the\s+page)/i,
      /\blanding\s*page.{0,30}(edit|update|change|modify|fix|adjust)/i,
      # Specific landing page modifications
      /\b(change|update|modify|fix)\s+.{0,20}(font|color|heading|headline|cta|button|text|image|video|section)/i,
      /\b(add|remove|delete)\s+.{0,20}(section|element|component|button|form|video|image)/i,
      # Styling requests in landing page context
      /\b(make\s+it|style|restyle|redesign)/i,
      # When user is clearly in landing page editor context
      /\b(this\s+page|the\s+page|current\s+page)\b.{0,30}(look|appear|display|show)/i
    ]
    return true if landing_page_patterns.any? { |p| msg.match?(p) }
    
    # WORKFLOW/AUTOMATION WORK → always delegate to Workflow Architect
    # The WA has specialized prompts for triggers, actions, conditions, and scheduling
    workflow_patterns = [
      # Creating automations/workflows
      /\b(build|design|create|generate|make|set\s*up)\s+(me\s+)?(a\s+)?(an?\s+)?(automation|workflow|trigger)/i,
      /\b(new|custom)\s+(automation|workflow)/i,
      # Editing automations
      /\b(edit|update|change|modify|fix)\s+.{0,30}(automation|workflow|trigger)/i,
      # Specific automation requests
      /\b(when|after|if)\s+.{0,30}(send\s+email|notify|update\s+record|create\s+record)/i,
      /\b(send\s+email|notify|alert)\s+when/i,
      /\b(daily|weekly|hourly|scheduled)\s+.{0,20}(report|task|job|sync)/i,
      /\bschedule\s+(a\s+)?(task|job|report|email|sync)/i,
      # Trigger types
      /\b(webhook|form\s+submit|record\s+change|status\s+change)\s*(trigger)?/i,
      # Action types
      /\bautomat(e|ically)\s+.{0,30}(send|create|update|notify|sync)/i
    ]
    return true if workflow_patterns.any? { |p| msg.match?(p) }
    
    # Explicit BUILD/DESIGN patterns → always delegate
    # These are creative tasks that specialist agents handle better
    build_patterns = [
      /\b(build|design|create)\s+(me\s+)?(a\s+)?(an?\s+)?(website|email|campaign)/i,
      /\b(generate|make)\s+(me\s+)?(a\s+)?(an?\s+)?(website|email|campaign)/i,
      /\b(help me|can you)\s+(build|create|design|make)/i,
      /\b(new|custom)\s+(email\s*campaign)/i,
      /\bcreate\s+(a\s+|an\s+)?(email\s+)?(campaign|sequence|series)\b/i,  # "create an email campaign"
      /\b(set up|setup)\s+(a\s+|an\s+)?(email|drip|nurture)\s*(campaign|sequence)/i
    ]
    return true if build_patterns.any? { |p| msg.match?(p) }
    
    # Integration intent with complex operations → delegate to integration agent
    if intent == :integration
      return true if msg.match?(/\b(sync|import|migrate|create|update|delete|push|send)\b/i)
    end
    
    # Module intent for data operations → delegate to module agent
    if intent == :module
      return true if msg.match?(/\b(create|add|update|delete|manage|fix)\b/i)
    end
    
    # Complex multi-step requests → delegate to planner
    return true if msg.match?(/\b(and then|after that|first.*then|step by step|workflow|plan)\b/i)
    
    false
  end
  
  def delegation_reason(message, classification)
    msg = message.downcase
    
    # Check for specific patterns first
    if msg.match?(/\b(landing\s*page|this\s+page|the\s+page)\b/i)
      return "The Landing Page Manager has specialized design tools and guaranteed access to all editing capabilities"
    elsif msg.match?(/\b(font|color|heading|headline|cta|button|section|element)\b/i)
      return "The Landing Page Manager specializes in design and layout modifications"
    elsif msg.match?(/\b(automation|workflow|trigger)\b/i)
      return "The Workflow Architect specializes in automations, triggers, and scheduled tasks"
    elsif msg.match?(/\b(when|after|if)\s+.{0,20}(send|notify|update|create)/i)
      return "The Workflow Architect can create automations based on triggers and conditions"
    elsif msg.match?(/\b(daily|weekly|scheduled|automat)/i)
      return "The Workflow Architect handles scheduled and automated tasks"
    elsif msg.match?(/\b(email|campaign)\b/i) && msg.match?(/\b(build|create|design)/i)
      return "Email campaigns benefit from specialist sequence design"
    elsif msg.match?(/\b(and then|first.*then|plan)\b/i)
      return "Multi-step tasks benefit from structured planning"
    end
    
    # Fall back to intent-based reasons
    case classification[:intent]
    when :build
      "Creative/design work is best handled by specialist agents"
    when :integration
      "Integration operations benefit from API expert knowledge"
    when :module
      "Module data operations benefit from schema expertise"
    else
      "Specialist agents have deeper domain knowledge"
    end
  end
  
  # Find agents for specific integrations
  def find_integration_agents(integration_slugs)
    return [] if integration_slugs.empty?
    
    begin
      registry = Amos::CapabilityRegistry.new(entity: @entity)
      integration_slugs.filter_map do |slug|
        agent = registry.integration_agents.find { |a| a[:slug]&.include?(slug) }
        agent if agent.present?
      end
    rescue
      []
    end
  end
  
  # Integration context preloading
  # KEY: Provides EXACT tool usage so Amos never has to guess
  def preload_integrations(message, classification)
    mentioned = classification[:mentioned_integrations] || []
    return { connected: [], knowledge: [], tool_usage: [] } if mentioned.empty?
    
    # Get connection status for mentioned integrations
    connections = Connection.includes(:integration, integration: :integration_operations)
                           .where(user: @user, entity: @entity, status: 'connected')
                           .joins(:integration)
                           .where(integrations: { slug: mentioned })
    
    connected = connections.map do |conn|
      ops = conn.integration.integration_operations.where(is_enabled: true).limit(10)
      {
        slug: conn.integration.slug,
        name: conn.integration.name,
        connection_id: conn.id,
        operations: ops.pluck(:name).first(5)
      }
    end
    
    # Pre-fetch integration knowledge hints
    knowledge = fetch_integration_knowledge(mentioned)
    
    # KEY ADDITION: Generate EXACT tool usage examples
    # This eliminates guessing - Amos gets copy-paste-ready syntax
    tool_usage = build_integration_tool_usage(mentioned, connected, message)
    
    {
      connected: connected,
      knowledge: knowledge,
      tool_usage: tool_usage,
      mentioned_but_not_connected: mentioned - connected.map { |c| c[:slug] }
    }
  rescue => e
    Rails.logger.warn "[Preprocessor] Integration preload failed: #{e.message}"
    { connected: [], knowledge: [], tool_usage: [] }
  end
  
  # Build EXACT tool usage examples for mentioned integrations
  # This is the KEY to eliminating guessing - Amos gets explicit syntax
  def build_integration_tool_usage(mentioned_slugs, connected_integrations, message)
    usage_examples = []
    msg = message.downcase
    
    mentioned_slugs.each do |slug|
      connection = connected_integrations.find { |c| c[:slug] == slug }
      next unless connection # Skip if not connected
      
      # Infer likely operation from message
      operation = infer_integration_operation(msg, slug, connection[:operations] || [])
      
      usage_examples << {
        slug: slug,
        status: :connected,
        example: build_example_call(slug, operation),
        available_operations: connection[:operations]
      }
    end
    
    # Also check for integrations mentioned but not connected
    (mentioned_slugs - connected_integrations.map { |c| c[:slug] }).each do |slug|
      usage_examples << {
        slug: slug,
        status: :not_connected,
        message: "#{slug.titleize} is not connected. User needs to connect it first."
      }
    end
    
    usage_examples
  end
  
  # Infer likely operation from message context
  def infer_integration_operation(message, slug, available_ops)
    # List/query operations
    if message.match?(/\b(list|show|get|pull|view|check)\s+(my\s+)?(all\s+)?/i)
      if message.match?(/customer|client|user|contact/i)
        return find_best_op(available_ops, %w[list_customers list_contacts get_customers])
      elsif message.match?(/invoice|bill|charge|payment/i)
        return find_best_op(available_ops, %w[list_invoices list_charges list_payments])
      elsif message.match?(/order|purchase|sale/i)
        return find_best_op(available_ops, %w[list_orders list_sales get_orders])
      elsif message.match?(/product|item|inventory/i)
        return find_best_op(available_ops, %w[list_products list_items get_products])
      end
    end
    
    # Create operations
    if message.match?(/\b(create|add|new|make)\s+/i)
      if message.match?(/customer|client|contact/i)
        return find_best_op(available_ops, %w[create_customer create_contact add_customer])
      elsif message.match?(/invoice|bill/i)
        return find_best_op(available_ops, %w[create_invoice create_bill])
      end
    end
    
    # Default: list customers is most common
    find_best_op(available_ops, %w[list_customers list_contacts get_company_info])
  end
  
  def find_best_op(available_ops, preferences)
    return preferences.first if available_ops.empty?
    preferences.find { |p| available_ops.include?(p) } || available_ops.first
  end
  
  # Build concrete example call - THIS IS THE KEY
  # Amos can literally copy this syntax
  def build_example_call(slug, operation)
    # Base pattern that works for ALL integrations
    base = {
      tool: 'execute_integration',
      params: {
        integration: slug,          # Always the slug, lowercase
        operation: operation,       # The specific operation
        params: {}                  # Additional params
      }
    }
    
    # Add integration-specific params
    case operation
    when /list_/
      base[:params][:params] = { limit: 10 }
    when /get_/
      base[:params][:params] = { id: '<RECORD_ID>' }
    when /create_/
      base[:params][:params] = { email: '...', name: '...' }
    end
    
    # Format as readable example
    <<~EXAMPLE.strip
      execute_integration(
        integration: "#{slug}",
        operation: "#{operation}",
        params: #{base[:params][:params].to_json}
      )
    EXAMPLE
  end
  
  # Module context preloading
  def preload_modules(message, classification)
    mentioned = classification[:mentioned_modules] || []
    
    # Get active modules
    active = @entity.app_modules.active.pluck(:name, :slug)
    
    # If specific modules mentioned, get their schemas
    schemas = {}
    if mentioned.any?
      @entity.app_modules.where(slug: mentioned).each do |mod|
        schemas[mod.slug] = mod.object_schemas.pluck(:name)
      end
    end
    
    {
      active: active,
      mentioned: mentioned,
      schemas: schemas
    }
  rescue => e
    Rails.logger.warn "[Preprocessor] Module preload failed: #{e.message}"
    { active: [], mentioned: [], schemas: {} }
  end
  
  # ═══════════════════════════════════════════════════════════════
  # CONTEXT INJECTION (Compact for prompt)
  # ═══════════════════════════════════════════════════════════════
  
  def build_context_injection(results, classification)
    parts = []
    
    # Canvas context
    if results[:canvas][:needs_freeform]
      # Integration query detected - no built-in canvas, will need freeform
      parts << "[USE: create_freeform_canvas to display external/integration data]"
    elsif results[:canvas][:canvas] && results[:canvas][:canvas] != :keep_current
      parts << "[CANVAS: #{results[:canvas][:canvas]} will load]"
    elsif @current_canvas.present?
      parts << "[VIEW: #{@current_canvas}]"
    end
    
    # Intent hint
    parts << "[INTENT: #{classification[:intent]}]" if classification[:confident]
    
    # Tool focus
    if results[:tools][:categories].any?
      parts << "[TOOLS: #{results[:tools][:categories].join(', ')} focused, #{results[:tools][:count]} available]"
    end
    
    # Agent hint - make delegation prominent when appropriate
    if results[:agents][:delegate_first] && results[:agents][:top_agent]
      agent = results[:agents][:top_agent]
      reason = results[:agents][:delegation_reason]
      parts << "⚡ [DELEGATE TO: #{agent[:name]} (#{agent[:slug]})]"
      parts << "[REASON: #{reason}]"
    elsif results[:agents][:top_agent]
      agent = results[:agents][:top_agent]
      parts << "[AGENT AVAILABLE: #{agent[:name]} if needed]"
    end
    
    # Integration context - THE KEY: Provide EXACT tool usage
    if results[:integrations][:connected].any?
      connected = results[:integrations][:connected].map { |c| c[:name] }.join(', ')
      parts << "[INTEGRATIONS: #{connected} connected]"
      
      # EXACT TOOL USAGE - This eliminates guessing
      results[:integrations][:tool_usage]&.each do |usage|
        if usage[:status] == :connected
          parts << ""
          parts << "[#{usage[:slug].upcase} USAGE]"
          parts << "#{usage[:example]}"
          parts << "Operations: #{usage[:available_operations]&.join(', ')}"
        elsif usage[:status] == :not_connected
          parts << "[#{usage[:slug].upcase}: NOT CONNECTED - #{usage[:message]}]"
        end
      end
      
      # Knowledge hints (API quirks, pagination, etc.)
      results[:integrations][:knowledge].each do |hint|
        parts << "[#{hint[:integration].upcase} TIP: #{hint[:tip]}]"
      end
    end
    
    # Module context
    if results[:modules][:mentioned].any?
      schemas = results[:modules][:schemas].map { |slug, objs| "#{slug}(#{objs.join(',')})" }.join(', ')
      parts << "[MODULES: #{schemas}]"
    end
    
    parts.join("\n")
  end
  
  # ═══════════════════════════════════════════════════════════════
  # HELPER METHODS
  # ═══════════════════════════════════════════════════════════════
  
  def connected_integration_slugs
    @connected_slugs ||= Connection.includes(:integration)
                                   .where(user: @user, entity: @entity, status: 'connected')
                                   .map { |c| c.integration.slug }
  rescue
    []
  end
  
  def active_module_names
    @active_modules ||= @entity.app_modules.active.pluck(:name, :slug)
  rescue
    []
  end
  
  def infer_categories_from_tools(tool_names, classification)
    categories = Set.new
    
    # From intent
    case classification[:intent]
    when :view then categories << :visualization
    when :create_data then categories << :data_mutation
    when :build then categories << :delegation
    when :integration then categories << :integrations
    when :module then categories << :modules
    end
    
    # From tool names
    tool_names.each do |name|
      categories << :communication if name.include?('email') || name.include?('contact')
      categories << :integrations if name.include?('integration') || name.include?('execute')
      categories << :visualization if name.include?('canvas') || name.include?('load')
      categories << :data_mutation if name.include?('create') || name.include?('update')
    end
    
    categories.to_a
  end
  
  def fetch_integration_knowledge(integration_slugs)
    hints = []
    
    integration_slugs.each do |slug|
      case slug
      when 'quickbooks'
        hints << {
          integration: 'quickbooks',
          tip: "Uses QBL query language: SELECT * FROM Invoice WHERE Balance > '0'"
        }
      when 'stripe'
        hints << {
          integration: 'stripe',
          tip: "Uses cursor pagination: limit, starting_after"
        }
      when 'gmail'
        hints << {
          integration: 'gmail',
          tip: "Uses label-based filtering and base64url encoding"
        }
      end
    end
    
    hints
  end
end

