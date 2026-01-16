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
  # Increased from 150ms to 500ms - RAG-based tool discovery needs more time
  # This still saves latency since all 5 threads run in parallel (max 500ms vs 5*500ms)
  THREAD_TIMEOUT_MS = 500
  
  # Minimum tools to always include (safety net)
  MINIMUM_TOOLS = 10
  
  attr_reader :user, :entity, :current_canvas, :session_id
  
  def initialize(user:, entity:, current_canvas: nil, session_id: nil)
    @user = user
    @entity = entity
    @current_canvas = current_canvas
    @session_id = session_id
  end
  
  # ═══════════════════════════════════════════════════════════════
  # MAIN ENTRY POINT - Runs all preprocessing in parallel
  # ═══════════════════════════════════════════════════════════════
  
  def preprocess(message:, conversation_context: nil)
    start_time = Time.current
    
    # PHASE 1: Quick regex classification (instant, handles 70% of cases)
    quick_classification = quick_classify(message)
    
    # PHASE 2: Parallel preprocessing threads
    threads = launch_parallel_threads(message, quick_classification, conversation_context)
    
    # Wait for threads with timeout
    results = collect_thread_results(threads)
    
    # PHASE 3: Build compact context injection
    context_inject = build_context_injection(results, quick_classification)
    
    latency_ms = ((Time.current - start_time) * 1000).round
    
    {
      # Routing decisions
      canvas: results[:canvas][:canvas] || :keep_current,
      canvas_delegate: results[:canvas][:delegate_to_amos],
      suggested_model: quick_classification[:model] || 'qwen3-next-80b',
      
      # Pre-discovered resources
      tools: results[:tools][:tool_names] || [],
      tool_categories: results[:tools][:categories] || [],
      suggested_agents: results[:agents][:agents] || [],
      
      # Team-first: delegation recommendations
      delegate_first: results[:agents][:delegate_first] || false,
      delegation_target: results[:agents][:top_agent],
      delegation_reason: results[:agents][:delegation_reason],
      
      # Context for integrations and modules
      integration_context: results[:integrations],
      module_context: results[:modules],
      
      # Compact injection for prompt
      context_inject: context_inject,
      
      # Metadata
      latency_ms: latency_ms,
      classification_method: quick_classification[:method],
      threads_completed: results[:completed_count],
      timestamp: Time.current
    }
  end
  
  private
  
  # ═══════════════════════════════════════════════════════════════
  # PHASE 1: QUICK CLASSIFICATION (Regex-based, instant)
  # ═══════════════════════════════════════════════════════════════
  
  def quick_classify(message)
    # Intent classification
    intent = classify_intent(message)
    
    # Model suggestion based on intent
    model = suggest_model(message, intent)
    
    # Extract mentioned entities
    mentioned = extract_mentions(message)
    
    {
      intent: intent,
      model: model,
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
  def suggest_model(message, intent)
    case intent
    when :reasoning
      'deepseek-r1' # Best for complex reasoning
    when :view
      # Simple canvas loading can use faster model
      if message.match?(/^\s*(show|view|list)\s+(my\s+)?\w+\s*$/i)
        'qwen-3-32b' # 2x faster for simple requests
      else
        'qwen3-next-80b'
      end
    else
      'qwen3-next-80b' # Default powerhouse
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
  # INDIVIDUAL PRELOADERS
  # ═══════════════════════════════════════════════════════════════
  
  # Canvas preloading (uses existing CanvasRouterService)
  def preload_canvas(message)
    router = CanvasRouterService.new(entity: @entity, current_canvas: @current_canvas)
    router.route(message: message, use_llm_fallback: false) # Regex only for speed
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
  def should_delegate_first?(message, classification)
    intent = classification[:intent]
    
    # BUILD intent → always delegate (creative work)
    return true if intent == :build
    
    # Integration intent with complex operations → delegate to integration agent
    if intent == :integration
      return true if message.match?(/\b(sync|import|create|update|delete)\b/i)
    end
    
    # Module intent for data operations → delegate to module agent
    if intent == :module
      return true if message.match?(/\b(create|add|update|delete|manage)\b/i)
    end
    
    false
  end
  
  def delegation_reason(message, classification)
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
  def preload_integrations(message, classification)
    mentioned = classification[:mentioned_integrations] || []
    return { connected: [], knowledge: [] } if mentioned.empty?
    
    # Get connection status for mentioned integrations
    connections = Connection.includes(:integration)
                           .where(user: @user, entity: @entity, status: 'connected')
                           .joins(:integration)
                           .where(integrations: { slug: mentioned })
    
    connected = connections.map do |conn|
      {
        slug: conn.integration.slug,
        name: conn.integration.name,
        connection_id: conn.id,
        operations_count: conn.integration.integration_operations.count
      }
    end
    
    # Pre-fetch integration knowledge hints
    knowledge = fetch_integration_knowledge(mentioned)
    
    {
      connected: connected,
      knowledge: knowledge,
      mentioned_but_not_connected: mentioned - connected.map { |c| c[:slug] }
    }
  rescue => e
    Rails.logger.warn "[Preprocessor] Integration preload failed: #{e.message}"
    { connected: [], knowledge: [] }
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
    if results[:canvas][:canvas] && results[:canvas][:canvas] != :keep_current
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
    
    # Integration context
    if results[:integrations][:connected].any?
      connected = results[:integrations][:connected].map { |c| c[:name] }.join(', ')
      parts << "[INTEGRATIONS: #{connected} connected]"
      
      # Knowledge hints
      results[:integrations][:knowledge].each do |hint|
        parts << "[#{hint[:integration].upcase}: #{hint[:tip]}]"
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

