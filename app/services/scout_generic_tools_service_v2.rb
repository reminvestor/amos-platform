# This is the MAIN Scout service that handles all LLM interactions with tools
# 
# IMPORTANT: This is the PRIMARY prompt being used in unified mode
# The prompt is built in the build_system_prompt method below
# 
# Flow: Orchestrator → SimpleQueryHandler → ScoutToolsService → THIS SERVICE
class ScoutGenericToolsServiceV2
  attr_reader :user, :entity, :session_id, :agent_loadout, :model
  attr_accessor :suggested_canvas, :canvas_data

  def initialize(user, entity, session_id, agent_loadout: nil, model: nil)
    @user = user
    @entity = entity
    @session_id = session_id
    @agent_loadout = agent_loadout
    @model = model # Model to use (defaults to ENV['BEDROCK_DEFAULT_MODEL'] or 'claude-sonnet-4-5')
    @ai_service = BedrockService.new(user: user, entity: entity)
    @ai_provider_name = Rails.application.config.ai_service.to_s.capitalize
    @tool_catalog = Tools::ToolCatalog.instance
    @suggested_canvas = nil
    @canvas_data = {}
    @saved_message_content = Set.new
    @messages_saved_during_streaming = false
    @context = {}
    @sources = [] # Track sources from tool responses
    @model_used = nil # Track actual model used (may differ from requested due to fallback)
    @model_name = nil # Human-readable model name
    @canvas_already_broadcast = false # Track if canvas was broadcast during tool execution
    
    # AMOS Orchestrator integration for platform awareness
    @amos_integration = Amos::ScoutIntegration.new(entity: entity, user: user) rescue nil
  end

  def set_context(context = {})
    @context = @context.merge(context)
  end

  # Set model selection mode (:auto, :fast, :balanced, :powerful)
  def set_model_mode(mode)
    @model_mode = mode
  end

  # Preprocess message for model selection and canvas routing
  # Runs in parallel for minimal latency impact
  def preprocess_message(user_message, current_canvas = nil)
    preprocessor = ScoutPreprocessorService.new(
      entity: @entity,
      current_canvas: current_canvas,
      user: @user
    )

    mode = @model_mode || :auto
    result = preprocessor.preprocess(message: user_message, mode: mode)

    # Update model if auto-selected
    if mode == :auto || @model.nil?
      @model = result[:model]
      Rails.logger.info "[Scout] Auto-selected model: #{result[:model]} (tier: #{result[:model_tier]}, #{result[:model_reasoning]})"
    end

    # Store preprocessing result for context injection
    @preprocess_result = result
    result
  end

  # Truncate large tool results to prevent context overflow
  # Max characters for a single tool result (roughly 4 chars per token, aiming for ~8000 tokens max per result)
  MAX_TOOL_RESULT_CHARS = 32000
  
  def truncate_tool_result(result)
    json_str = result.to_json
    
    if json_str.length <= MAX_TOOL_RESULT_CHARS
      return json_str
    end
    
    Rails.logger.warn "⚠️ Truncating large tool result: #{json_str.length} chars → #{MAX_TOOL_RESULT_CHARS} chars"
    
    # Try to preserve structure by truncating intelligently
    if result.is_a?(Hash)
      # For hash results, try to truncate nested arrays/data
      truncated = truncate_hash_result(result)
      truncated_json = truncated.to_json
      if truncated_json.length <= MAX_TOOL_RESULT_CHARS
        return truncated_json
      end
    elsif result.is_a?(Array)
      # For array results, take fewer items
      truncated = result.first(10)
      truncated_json = truncated.to_json
      if truncated_json.length <= MAX_TOOL_RESULT_CHARS
        return truncated_json + "\n[... #{result.length - 10} more items truncated for context limit]"
      end
    end
    
    # Fallback: hard truncate with message
    json_str.first(MAX_TOOL_RESULT_CHARS - 100) + "\n\n[... TRUNCATED - result too large for context window. Total size: #{json_str.length} chars]"
  end
  
  def truncate_hash_result(hash, max_depth: 2, current_depth: 0)
    return "[nested data]" if current_depth > max_depth
    
    hash.transform_values do |value|
      case value
      when Array
        if value.length > 10
          value.first(10) + ["... #{value.length - 10} more items"]
        else
          value.map { |v| v.is_a?(Hash) ? truncate_hash_result(v, max_depth: max_depth, current_depth: current_depth + 1) : v }
        end
      when Hash
        truncate_hash_result(value, max_depth: max_depth, current_depth: current_depth + 1)
      when String
        value.length > 2000 ? value.first(2000) + "... [truncated]" : value
      else
        value
      end
    end
  end

  # Parse JSON from tool arguments with repair for common LLM errors
  # Handles missing quotes, trailing commas, etc.
  def parse_tool_arguments(args_string)
    return {} if args_string.blank?
    return args_string if args_string.is_a?(Hash)
    
    # First try standard parse
    JSON.parse(args_string)
  rescue JSON::ParserError => e
    Rails.logger.warn "⚠️ JSON parse failed, attempting repair: #{e.message}"
    
    # Try to repair common LLM JSON errors
    repaired = repair_json(args_string)
    
    begin
      JSON.parse(repaired)
    rescue JSON::ParserError => repair_error
      Rails.logger.error "❌ JSON repair failed: #{repair_error.message}"
      Rails.logger.error "   Original: #{args_string}"
      Rails.logger.error "   Repaired: #{repaired}"
      raise # Re-raise the original error
    end
  end
  
  # Repair common JSON errors from LLMs
  def repair_json(json_string)
    repaired = json_string.dup
    
    # Fix missing quotes before keys: {key: "value"} → {"key": "value"}
    # Pattern: { or , followed by whitespace and unquoted word and :
    repaired.gsub!(/([{,])\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*:/) do
      "#{$1}\"#{$2}\":"
    end
    
    # Fix trailing commas before closing braces: {a: 1,} → {a: 1}
    repaired.gsub!(/,\s*([}\]])/, '\1')
    
    # Fix single quotes to double quotes (but be careful with apostrophes)
    # Only convert if it looks like a JSON string: 'value' → "value"
    repaired.gsub!(/:\s*'([^']*)'/, ':"\\1"')
    
    # Remove any trailing garbage after the JSON object
    if repaired.include?('{')
      # Find matching closing brace
      brace_count = 0
      end_pos = nil
      repaired.each_char.with_index do |char, idx|
        if char == '{'
          brace_count += 1
        elsif char == '}'
          brace_count -= 1
          if brace_count == 0
            end_pos = idx
            break
          end
        end
      end
      repaired = repaired[0..end_pos] if end_pos
    end
    
    Rails.logger.info "🔧 JSON repaired: #{repaired}" if repaired != json_string
    repaired
  end

  def process_message_with_tools_streaming(user_message, progress_callback, conversation_history = [], current_canvas = nil)
    @stop_after_delegation = false # Reset flag at start
    @canvas_already_broadcast = false # Reset canvas broadcast flag
    begin
      # PHASE 1: Parallel preprocessing (model selection + canvas routing)
      # This runs in ~20-50ms and doesn't block the main flow
      preprocess_result = preprocess_message(user_message, current_canvas)
      
      # Handle auto canvas loading (before Amos even starts)
      if preprocess_result[:canvas] && preprocess_result[:canvas] != :keep_current && !preprocess_result[:canvas_delegate]
        # Broadcast canvas load immediately - user sees it before Amos responds
        broadcast_auto_canvas(preprocess_result[:canvas], progress_callback)
      end

      # Build system prompt (now lighter - canvas logic offloaded)
      system_prompt = build_system_prompt(current_canvas)

      # Inject preprocessor context (very compact, ~20-50 tokens)
      if preprocess_result[:context_inject].present?
        system_prompt = inject_canvas_context(system_prompt, preprocess_result[:context_inject])
      end

      # Enhance user message with context
      enhanced_message = enhance_message_with_canvas_context(user_message, current_canvas)

      # Format conversation
      conversation_messages = format_conversation_for_ai(conversation_history, enhanced_message)

      Rails.logger.info "Sending #{conversation_messages.length} messages to #{@ai_provider_name}"
      progress_callback&.call("🤖 Processing request...")

      # SMART ROUTING: Detect if tools are needed
      # This can save 15K+ tokens for simple requests like "hello"
      routing = smart_route_request(user_message)
      
      if routing[:needs_tools]
        # Get filtered tools - use selective loading if categories specified
        if routing[:tool_categories].present? && routing[:tool_categories] != [:general]
          tools = get_selective_tools(routing[:tool_categories], user_message)
          Rails.logger.info "🎯 Smart routing: #{tools.length} selective tools for #{routing[:tool_categories].join(', ')}"
        else
          tools = get_filtered_tools(prompt: user_message)
          Rails.logger.info "🔧 Using #{tools.length} tools (full discovery)"
        end
        
        # Update model if smart router suggests a different one
        if routing[:suggested_model].present? && @model.nil?
          @model = routing[:suggested_model]
          Rails.logger.info "🧠 Smart routing selected model: #{@model}"
        end
      else
        # NO TOOLS NEEDED - skip all tool tokens! 
        tools = []
        Rails.logger.info "⚡ Smart routing: NO TOOLS (#{routing[:reasoning]})"
        
        # Use faster model for simple responses
        @model ||= routing[:suggested_model] || 'qwen-3-32b'
        Rails.logger.info "⚡ Using fast model: #{@model}"
      end

      # Stream the response
      accumulated_content = ""
      tool_calls = []
      streaming_started = false

      @ai_service.send_message_streaming(
        system_prompt,
        conversation_messages,
        model: @model,
        max_tokens: 25000,
        temperature: 0.7,
        json_mode: false,
        tools: tools,
        enable_prompt_caching: true
      ) do |chunk|
        handle_streaming_chunk(chunk, accumulated_content, tool_calls, streaming_started, progress_callback)
        streaming_started = true if chunk[:type] == :content
      end

      # Execute any tool calls
      if tool_calls.any?
        tool_results = execute_tool_calls(tool_calls, progress_callback)

        # Add the assistant's response with tool calls to conversation
        conversation_messages << {
          role: "assistant",
          content: [
            { type: "text", text: accumulated_content.strip.presence || "I'll help you with that." },
            *tool_calls.map do |tool_call|
              # Parse arguments - handle string, hash, or empty (with JSON repair)
              input = parse_tool_arguments(tool_call[:arguments])

              {
                type: "tool_use",
                tool_use: {
                  id: tool_call[:id],
                  name: tool_call[:name],
                  input: input
                }
              }
            end
          ].compact
        }

        # Get final response after tools
        final_response = get_continuation_after_tools(
          system_prompt,
          conversation_messages,
          tool_calls,
          tool_results,
          progress_callback
        )

        # If delegation occurred, return appropriate response with the delegation message
        if @stop_after_delegation
          # Use the delegation message if we have one, otherwise use accumulated content
          delegation_response = @delegation_message || accumulated_content
          
          response = {
            final_response: {
              message: delegation_response,
              message_already_saved: @messages_saved_during_streaming,
              delegation_occurred: true
            },
            tools_used: tool_calls.map { |tc| tc[:name] },
            sources: @sources,
            model_used: @model_used,
            model_name: @model_name,
            delegation_occurred: true
          }
          
          # Only include canvas info if a canvas was suggested
          if @suggested_canvas
            response[:canvas_type] = @suggested_canvas
            response[:canvas_data] = @canvas_data
          else
            response[:canvas_type] = "conversation"
          end
          
          response
        else
        final_response
        end
      else
        # No tools used, return the accumulated content
        response = {
          final_response: {
            message: accumulated_content,
            message_already_saved: @messages_saved_during_streaming,
            delegation_occurred: @stop_after_delegation || false
          },
          tools_used: [],
          sources: @sources,
          model_used: @model_used,
          model_name: @model_name,
          delegation_occurred: @stop_after_delegation || false
        }
        
        # Only include canvas info if a canvas was suggested
        if @suggested_canvas
          response[:canvas_type] = @suggested_canvas
          response[:canvas_data] = @canvas_data
        else
          response[:canvas_type] = "conversation"
        end
        
        response
      end
    rescue => e
      Rails.logger.error "ScoutGenericToolsServiceV2 error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      {
        final_response: {
          message: "I encountered an error: #{e.message}",
          error: true
        },
        canvas_type: "conversation",
        tools_used: []
      }
    end
  end

  def execute_tool_by_name(tool_name, args, progress_callback = nil)
    Rails.logger.info "🔧 Executing tool: #{tool_name}"

    # Check if tool is allowed by agent loadout
    if @agent_loadout && !@agent_loadout.tool_allowed?(tool_name)
      Rails.logger.warn "Tool #{tool_name} not allowed by agent loadout"
      return { success: false, error: "Tool not permitted for current context" }
    end

    # Special handling for canvas loading
    if tool_name == "load_canvas"
      return execute_load_canvas(args, progress_callback)
    end

    # Create context that will be shared with the tool
    # IMPORTANT: Memory tools need session_id to access Redis storage
    tool_context = {
      session_id: @session_id,
      canvas_suggestion: nil,
      canvas_data: {},
      **@context  # Include any additional context (like task_session)
    }

    # Execute through tool catalog
    result = @tool_catalog.execute_tool(
      tool_name,
      args,
      user: @user,
      entity: @entity,
      context: tool_context,
      progress_callback: progress_callback
    )

    # Handle any canvas suggestions from tools
    if tool_context[:canvas_suggestion]
      safe_load_canvas(tool_context[:canvas_suggestion], tool_context[:canvas_data] || {})
      
      # Broadcast canvas update immediately for all canvas types
      if progress_callback && @suggested_canvas
        progress_callback.call({
          type: "canvas_update",
          canvas_type: @suggested_canvas,
          canvas_data: @canvas_data
        })
        # Mark that we've already broadcast this canvas
        @canvas_already_broadcast = true
      end
    end

    result
  end

  private

  # Smart routing to detect if tools are needed
  # Returns: { needs_tools: bool, tool_categories: [], suggested_model: string, reasoning: string }
  def smart_route_request(message)
    router = SmartRequestRouter.new(entity: @entity, user: @user)
    result = router.analyze(message: message)
    
    Rails.logger.info "[SmartRouter] #{result[:needs_tools] ? '🔧' : '⚡'} needs_tools=#{result[:needs_tools]}, method=#{result[:detection_method]}, latency=#{result[:latency_ms]}ms"
    
    result
  rescue => e
    Rails.logger.error "[SmartRouter] Error: #{e.message}, defaulting to tools"
    { needs_tools: true, tool_categories: [:general], suggested_model: nil, reasoning: 'Router error' }
  end

  # Get selective tools based on detected categories
  def get_selective_tools(categories, message)
    router = SmartRequestRouter.new(entity: @entity, user: @user)
    tool_names = router.tools_for_categories(categories)
    
    # Get all available tools then filter to just the ones we need
    all_tools = get_filtered_tools(prompt: message)
    
    # Keep tools that match the category OR are in our selective list
    # Also always include core tools like ask_user
    core_always = %w[ask_user get_platform_capabilities]
    
    all_tools.select do |tool|
      name = tool[:name] || tool["name"]
      tool_names.include?(name) || core_always.include?(name)
    end
  end

  def get_filtered_tools(prompt: nil)
    # ═══════════════════════════════════════════════════════════════
    # SCOUT TOOL ACCESS - TIERED SYSTEM:
    # TIER 1: CORE_TOOLS (~13 tools) - Scout's native abilities, always available
    # TIER 2: CONFIGURABLE_TOOLS - User-enabled extensions
    # TIER 3: EXCLUDED_TOOLS - Always delegate to agents
    # ═══════════════════════════════════════════════════════════════
    
    # Get or create Scout's configuration from DB
    scout_config = nil
    if @entity.present?
      scout_config = ScoutLoadoutConfiguration.for_entity(@entity)
    end

    # Get effective tool allowlist (CORE + user-configured)
    if scout_config.present?
      effective_allowlist = scout_config.effective_tool_allowlist
      
      # Create/update the agent loadout with Scout's specific tools
      @agent_loadout ||= AgentLoadout.new
      @agent_loadout.tool_allowlist = effective_allowlist
      @agent_loadout.agent_role = "main_chat"
      
      # Log tool summary (single line)
      stats = scout_config.tool_stats
      tiered = scout_config&.use_tiered_discovery ? "+discovery" : ""
      Rails.logger.info "🤖 Scout: #{stats[:total_enabled]} tools (#{stats[:core_count]} core, #{stats[:configured_count]} configured#{tiered})"
    end

    # Get tools from catalog
    tools = @tool_catalog.get_bedrock_tools(
      agent_loadout: @agent_loadout,
      enable_caching: true,
      user: @user,
      entity: @entity,
      prompt: prompt
    )

    # Exclude dynamic tools for Scout (main_chat uses only class-based tools)
    if @agent_loadout && @agent_loadout.agent_role == "main_chat"
      tools.reject! do |tool| 
        tool_name = tool[:name] || tool["name"]
        tool_entry = @tool_catalog.tools[tool_name]
        tool_entry && tool_entry[:type] == :definition
      end
    end

    # Final exclusion list - tools that should NEVER be available to Scout
    # These are handled by EXCLUDED_TOOLS in ScoutLoadoutConfiguration
    # but we double-check here for safety
    excluded_tools = ScoutLoadoutConfiguration::EXCLUDED_TOOLS

    tools.reject { |tool| excluded_tools.include?(tool["name"] || tool[:name]) }
  end

  def format_current_canvas_for_prompt(canvas)
    return "" unless canvas.present?
    
    # Convert to hash if needed
    if canvas.respond_to?(:to_unsafe_h)
      canvas = canvas.to_unsafe_h
    elsif canvas.respond_to?(:to_h) && !canvas.is_a?(Hash)
      canvas = canvas.to_h
    end
    
    return "" unless canvas.is_a?(Hash)
    
    canvas_type = canvas["type"] || canvas[:type]
    canvas_data = canvas["data"] || canvas[:data] || {}
    
    # Log canvas details for debugging
    if canvas_type == "landing_page_editor"
      Rails.logger.info "🎯 Scout Canvas Context - Type: #{canvas_type}"
      Rails.logger.info "🎯 Scout Canvas Data: #{canvas_data.inspect}"
    end
    
    # Format based on canvas type
    case canvas_type
    when "document_viewer"
      asset_id = canvas_data["asset_id"] || canvas_data[:asset_id]
      filename = canvas_data["filename"] || canvas_data[:filename]
      "CURRENT VIEW: Document '#{filename}' (ID: #{asset_id})"
    when "document_search_results"
      query = canvas_data["query"] || canvas_data[:query]
      "CURRENT VIEW: Document search results for '#{query}'"
    when "landing_page_editor"
      page_id = canvas_data["landing_page_id"] || canvas_data[:landing_page_id]
      Rails.logger.info "🎯 Scout Landing Page Editor ID: #{page_id}"
      "CURRENT VIEW: Landing page editor (ID: #{page_id})"
    when "campaign_viewer", "email_campaign_viewer"
      "CURRENT VIEW: Email campaigns list"
    when "contact_viewer"
      "CURRENT VIEW: Contacts list"
    when "analytics_dashboard"
      "CURRENT VIEW: Analytics dashboard"
    when "parallel_tasks"
      "CURRENT VIEW: Task monitor"
    else
      "CURRENT VIEW: #{canvas_type&.humanize || 'Unknown'}"
    end
  end

  def build_system_prompt(current_canvas = nil)
    # Use AmosIdentity core identity as the foundation
    space_definition = @user&.active_space_definition
    ai_identity = AmosIdentity.build_system_prompt(
      user: @user,
      space_definition: space_definition
    )

    # Current date/time in user's timezone (default to Pacific)
    current_time = Time.current.in_time_zone('America/Los_Angeles')
    current_datetime = current_time.strftime("%A, %B %d, %Y at %I:%M %p %Z")

    available_models = ScoutDataRegistry.available_object_types
    
    # Load business context
    business_context = format_business_context_for_prompt

    # Load additional context
    user_memories = format_user_memories_for_prompt
    scout_personality = format_scout_personality_for_prompt
    scout_learnings = format_scout_learnings_for_prompt
    conversation_summaries = format_conversation_summaries_for_prompt
    ai_rulesets = format_ai_rulesets_for_prompt

    prompt = <<~PROMPT
      #{ai_identity}

      📅 CURRENT DATE/TIME: #{current_datetime}
      
      #{scout_personality}
      
      #{business_context}
      
      #{user_memories}
      
      #{scout_learnings}
      
      #{conversation_summaries}
      
      #{format_current_canvas_for_prompt(current_canvas)}

      #{ai_rulesets}

      ═══════════════════════════════════════════════════════════════
      🎯 SCOUT IDENTITY - WHO YOU ARE
      ═══════════════════════════════════════════════════════════════
      
      You are the orchestrator and concierge for the AMOS platform.
      Your job: SHOW data, ROUTE to specialists, REMEMBER context.
      
      Scout SHOWS and ROUTES. Agents CREATE and BUILD.
      
      🎯 COMMUNICATION STYLE:
      • Be concise and action-focused
      • Don't narrate what you're doing - just DO it
      • Found documents? SHOW them immediately
      • Focus on the CURRENT request
      • Get straight to the answer
      • When referencing canvases/visualizations, say "as displayed" (NOT "above" - the canvas is beside the chat, not above it)

      ═══════════════════════════════════════════════════════════════
      👁️ YOUR NATIVE ABILITIES (always available)
      ═══════════════════════════════════════════════════════════════
      
      SEE & SHOW DATA:
      • get_data - Query contacts, campaigns, landing pages, etc.
      • load_canvas - Display BUILT-IN canvases (dashboard, contacts, campaigns, etc.)
      • create_freeform_canvas - FALLBACK when no built-in canvas exists
      • save_visualization - Save a visualization when user explicitly asks to keep it
      
      ⚡ CANVAS PRIORITY (use in this order):
      1. FIRST: Check if a BUILT-IN CANVAS exists for the data type:
         - contacts, contact_viewer → show contacts
         - campaigns, email_campaigns → show campaigns
         - landing_pages, landing_page_viewer → show landing pages
         - dashboard → overview dashboard
         - analytics → analytics dashboard
         - scheduled_tasks → scheduled tasks
         - module_manager → custom modules
         Use load_canvas for these!
         
      2. FALLBACK: If NO built-in canvas exists → use create_freeform_canvas
         - External data (Stripe customers, API results, etc.)
         - Custom reports not covered by built-in canvases
         - User explicitly asks for "freeform" or "custom view"
         - Any data that doesn't fit a pre-built canvas
         
      create_freeform_canvas gives you full HTML/CSS/JS freedom for:
      - Tables, cards, charts, reports, lists, summaries
      - Libraries available: Chart.js, D3, Plotly, Mermaid, etc.
      - EPHEMERAL display - not permanently saved
      
      EXAMPLES:
      • "Show me my contacts" → load_canvas(contact_viewer)
      • "Show me my campaigns" → load_canvas(email_campaigns)  
      • "Show me my Stripe customers" → create_freeform_canvas (no built-in canvas!)
      • "Create a custom view for this data" → create_freeform_canvas
      
      SEARCH & DISCOVER:
      • web_search - Get real-time information (stocks, weather, news, etc.)
      • query_document_content - Search all uploaded documents
      • read_document - Read specific document content
      
      CONNECT & ORCHESTRATE:
      • find_best_agent - Find the best specialist agent for a task (PREFERRED - uses historical data)
      • propose_task_to_agent - CHECK if agent can handle task (handshake)
      • delegate_to_agent - Hand off work to specialists (after handshake)
      • respond_to_agent - Handle agent questions
      • list_connections - See what integrations are connected
      
      AVAILABLE DATA MODELS: #{available_models.join(', ')}

      ═══════════════════════════════════════════════════════════════
      🧠 UNIFIED MEMORY - You Remember Everything!
      ═══════════════════════════════════════════════════════════════
      
      You have ONE CONTINUOUS CONVERSATION with this user - no sessions!
      Your memory works in layers, like human memory:
      
      📍 ACTIVE (instant): Last 15 messages - always in your context
      🕐 RECENT (fast): Past week - searchable history
      📚 LONG-TERM: All history - summaries and RAG search
      
      MEMORY TOOLS:
      🔍 SEARCH & RECALL:
      • search_memory - Find specific info in past conversations (quick lookup)
      • recall_context - Jump back to a topic and restore full context
      
      💾 SAVE & STORE:
      • remember_this - When user says "remember that...", "always...", "never..."
      • bookmark_this - Save an output to revisit later (reports, analysis, etc.)
      • list_saved - Show user's saved bookmarks
      
      WHEN TO USE:
      • "What did we discuss about X?" → search_memory(query: "X")
      • "Go back to when we talked about Y" → recall_context(query: "Y")
      • "Remember that I prefer..." → remember_this(content: "...")
      • "Save this report" → bookmark_this(title: "...", description: "...")
      • "Show my saved items" → list_saved()
      
      KEY DIFFERENCE:
      • search_memory = quick lookup, returns matches
      • recall_context = restore full context, continue conversation from that point
      
      ⚠️ You REMEMBER this user across days/weeks. Reference past context naturally!

      ═══════════════════════════════════════════════════════════════
      🚨 CRITICAL: TOOL USAGE - NEVER HALLUCINATE
      ═══════════════════════════════════════════════════════════════
      
      YOU MUST FOLLOW THESE RULES EXACTLY:
      
      1. IF YOU NEED A TOOL AND HAVE IT → CALL IT via the tool API
         ✅ Right: Use the tool_use API to call web_search, get_data, etc.
         ❌ WRONG: Print {"tool": "web_search", ...} as text in your response
         ❌ WRONG: Say "I would call web_search with..." 
         
      2. IF YOU NEED DATA YOU DON'T HAVE → SAY SO, then delegate
         ✅ Right: "I need real-time data for this. Let me get an agent to help."
                   Then call delegate_to_agent or ask_agent_for_help
         ❌ WRONG: Make up an answer based on training data
         ❌ WRONG: Say "The temperature is 72°F" without calling a tool
         
      3. IF A QUESTION NEEDS EXTERNAL DATA → YOU NEED A TOOL
         Questions about: weather, stock prices, current events, live data,
         specific facts about companies/people/places → REQUIRE tools
         ✅ If you have web_search → USE IT
         ✅ If you don't have it → Delegate to Web Research agent
         ❌ NEVER answer from memory for real-time/factual queries
         
      4. WHEN IN DOUBT → DELEGATE
         If you're unsure whether you can answer accurately:
         → delegate_to_agent("Web Research", "I need help finding...")
         Better to ask for help than give a wrong answer!
      
      5. ANSWER FIRST, THEN OFFER TO GO DEEPER
         When the user asks a question, give them the answer AND offer smart follow-ups:
         
         ✅ GOOD: "You have **14 contacts** in your CRM. Would you like to filter by 
                   status, see recent additions, or explore specific segments?"
         ✅ GOOD: "Your campaigns are performing well - 32% open rate overall. Want me
                   to break this down by campaign, or show trends over time?"
         
         ❌ BAD: "Do you want total or filtered?" (asking INSTEAD of answering)
         ❌ BAD: "14 contacts." (just the number with no follow-up)
         
         This pattern shows you're CAPABLE (you answered) and PROACTIVE (you anticipated).
         Over time, use memory to learn what this specific user typically wants next!

      ═══════════════════════════════════════════════════════════════
      🔴 DECISION FRAMEWORK - FOLLOW THIS ORDER
      ═══════════════════════════════════════════════════════════════
      
      🔴 FIRST: CLASSIFY THE REQUEST (VIEW vs BUILD)
      ═══════════════════════════════════════════════════════════════
      
      VIEW/QUERY REQUESTS (Handle yourself with tools + LOAD CANVAS):
      • "How are my campaigns doing?" → get_data + load_canvas("campaign_viewer")
      • "Show me my contacts" → get_data + load_canvas("analytics_dashboard")
      • "What's my open rate?" → get_data + load_canvas("analytics_dashboard")
      • "Show my landing pages" → get_data + load_canvas("landing_page_viewer")
      • Keywords: show, view, how, what, status, performance, list, check
      🔴 ALWAYS pair data queries with a relevant canvas!
      
      BUILD/CREATE REQUESTS (Delegate to agents):
      • "Create a landing page" → delegate_to_agent
      • "Build an email campaign" → delegate_to_agent
      • Keywords: create, build, make, design, set up, connect, import
      
      ⚠️ CRITICAL: A request to VIEW data is NOT a request to BUILD!
      "How are my campaigns?" ≠ "Build a campaign"
      
      ═══════════════════════════════════════════════════════════════
      
      0️⃣ NEED EARLIER CONTEXT?
         • Quick lookup → search_memory(query: "topic")
         • Full context restore → recall_context(query: "topic")
         • "Remember that I always..." → remember_this(content: "...")
         • "Save this" → bookmark_this(title: "...", description: "...")
      
      1️⃣ NEED CURRENT/REAL DATA? (VIEW requests)
         • Stock prices, weather, news → web_search FIRST
         • CRM data, contacts, campaigns → get_data FIRST
         • Documents → query_document_content or read_document FIRST
         • Integration status → list_connections FIRST
         ⚠️ NEVER answer from memory if real-time data exists!
         
      2️⃣ SHOW IT VISUALLY! (Always for VIEW requests)
         🔴 ALWAYS load a canvas when answering data questions!
         • Campaigns → load_canvas("campaign_viewer") + get_data
         • Analytics/metrics → load_canvas("analytics_dashboard") + get_data
         • Landing pages → load_canvas("landing_page_viewer") + get_data
         • Documents → load_canvas("document_viewer") or load_canvas("document_search_results")
         • Charts → create_dynamic_visualization
         → Visual context is BETTER UX than text-only answers!
      
      2️⃣.5 CREATING/UPDATING DATA? → SCHEMA FIRST!
         🔴 ALWAYS call get_schema BEFORE create_object or update_object!
         • get_schema tells you required fields and valid values
         • Avoids wasted calls with missing/wrong fields
         • Example flow: get_schema("contact") → create_object("contacts", {...})
         ⚠️ NEVER guess field names - always check schema first!
      
      3️⃣ IS THIS A CREATION/BUILD TASK? → DELEGATE!
         • "Create a landing page" → delegate_to_agent
         • "Build an email campaign" → delegate_to_agent
         • "Connect to Stripe" → delegate_to_agent
         • "Import my contacts" → delegate_to_agent
         → find_best_agent to find the right specialist
         → delegate_to_agent IMMEDIATELY - don't gather requirements yourself
      
      4️⃣ COMPLEX REQUEST? → USE THE PLANNER!
         • Multi-step projects → delegate_to_planner
         • Requests with "and", "with", "complete system" → needs planning
         • Building something with multiple modules → needs planning
         → The Planner breaks it down into phases and steps
         → Each step gets the right agent assigned
         → Progress is tracked and failures are handled
         
         Example: "Build me a complete social media marketing system"
         → delegate_to_planner(request: "...", analysis: { complexity: "complex" })
         → Show the plan to user for approval
         → Execute step by step with execute_plan_step
      
      5️⃣ NO AGENT EXISTS? → CREATE ONE!
         • Recurring task with no agent → delegate to agent_architect
         • New integration needed → delegate to integration_architect
         → The platform EVOLVES to meet needs
      
      6️⃣ ONLY THEN: Answer from knowledge

      ═══════════════════════════════════════════════════════════════
      🎨 WHEN TO DELEGATE TO AGENTS (not your job)
      ═══════════════════════════════════════════════════════════════
      
      CONTENT CREATION → Delegate:
      • Landing pages → find_best_agent → propose_task_to_agent → delegate_to_agent
      • Email campaigns → delegate_to_agent
      • Blog posts, marketing content → delegate_to_agent
      
      BUILDING & INTEGRATION → Delegate:
      • Connect to Stripe/APIs → delegate_to_agent
      • Build workflows → delegate_to_agent
      • Create new tools → delegate_to_agent
      
      DATA OPERATIONS → Delegate:
      • Import contacts from CSV → delegate_to_agent
      • Data migration → delegate_to_agent
      
      DOCUMENT EXPORT → Delegate:
      • "Export as CSV" → delegate_to_agent(agent_type: "document_export_agent")
      • "Give me an Excel file" → delegate_to_agent(agent_type: "document_export_agent")
      • "Generate a PDF report" → delegate_to_agent(agent_type: "document_export_agent")
      • Any request for CSV, Excel, PDF output → delegate_to_agent
      → User can download from Work Items when complete
      
      DELEGATION FLOW (with Handshake Protocol):
      1. Say "One moment, let me find the right specialist..."
      2. Call find_best_agent(task_description: "...") to get the TOP agent recommendation
         ⚠️ DO NOT call list_available_agents - find_best_agent is better (uses performance data)
      3. Call propose_task_to_agent to CHECK if the agent can handle it:
         - If ACCEPTED → proceed to delegate_to_agent with the proposal_id
         - If REJECTED → try the suggested alternative, or inform user
      4. Call delegate_to_agent with proposal_id for guaranteed execution
      5. Stay silent - the agent will communicate through you
      
      🤝 HANDSHAKE PROTOCOL:
      Before delegating, ALWAYS check if the agent can do the task:
      
      propose_task_to_agent(
        agent_slug: "module_architect",
        task_description: "Update the A/B test record with variant IDs",
        tools_likely_needed: ["update_object", "get_data"]
      )
      
      🧠 AGENT DISCOVERY (only one tool needed):
      • find_best_agent - THE ONLY TOOL for finding agents (combines performance + semantic search)
        ⚠️ DO NOT use list_available_agents - it's deprecated
      • analyze_agent_performance - Check an agent's health and capabilities
      • repair_agent_failures - Fix capability gaps and route around issues
      
      If accepted: delegate_to_agent(agent_type: "module_architect", ..., proposal_id: 123)
      If rejected: Try the suggested_alternatives or inform user why task can't be done
      
      🔴 DO NOT gather requirements yourself! Let the agent ask its own questions.
      
      WRONG: "To create this, I need to know: 1. What's your product?"
      RIGHT: "Let me get our landing page specialist on that!" → propose_task → delegate

      ═══════════════════════════════════════════════════════════════
      🔴🔴🔴 CRITICAL: AGENT DELEGATIONS ARE OUT-OF-BAND 🔴🔴🔴
      ═══════════════════════════════════════════════════════════════
      
      When you delegate to an agent, it runs ASYNCHRONOUSLY in the background.
      You are FREE to continue helping the user with OTHER tasks immediately!
      
      RULES:
      1. 🚀 FIRE AND FORGET: After delegation, the agent handles everything
      2. 🔀 NON-BLOCKING: User can ask you anything else while agents work
      3. 📬 SEPARATE CHANNEL: Agent questions appear in a queue, not in chat
      4. 🆕 TREAT EACH MESSAGE FRESH: New user message = evaluate independently
      
      EXAMPLE FLOW:
      • User: "Create a landing page" → You delegate → Agent is now working
      • User: "How are my email campaigns?" → THIS IS A NEW REQUEST!
         → Answer about campaigns using get_data
         → Do NOT re-engage the landing page agent
         → The landing page work continues separately
      
      WHEN TO USE respond_to_agent:
      • ONLY when user explicitly answers an agent's pending question
      • "The headline should be 'Save 50% Today'" → This answers the agent
      • "How are my campaigns?" → This is NOT an agent answer, handle it yourself!
      
      🔴 NEVER re-delegate to an agent that's already working on a task!
      🔴 NEVER confuse a new topic with a pending agent's context!
      🔴 Each user message is independent unless they're explicitly responding to an agent question

      ═══════════════════════════════════════════════════════════════
      🔴 WEB SEARCH - USE IT PROACTIVELY
      ═══════════════════════════════════════════════════════════════
      
      ALWAYS USE web_search FOR:
      • Stock prices, exchange rates, crypto prices
      • Weather forecasts
      • Current news and events
      • Competitor research
      • Product comparisons and pricing
      • Any "current", "latest", "today" questions
      • Any factual question you're not 100% certain about
      
      NEVER say "I don't have real-time data" - you DO via web_search!
      NEVER say "My training data is from..." - SEARCH for current info!

      ═══════════════════════════════════════════════════════════════
      📄 DOCUMENTS - SEARCH AND SHOW
      ═══════════════════════════════════════════════════════════════

      • [ATTACHED FILES] present → read_document immediately
      • "Find document about X" → query_document_content(query: "X")
      • "Show my documents" → query_document_content then load_canvas("document_search_results")
      
      🔴 CRITICAL: ALWAYS RE-QUERY BEFORE LOADING A SPECIFIC DOCUMENT!
      When user says "show me the X document" from a previous search:
      1. FIRST: query_document_content(query: "document name or topic")
      2. Get the asset_id from the results (look in metadata.rag_document_id)
      3. THEN: load_canvas("document_viewer", { asset_id: CORRECT_ID, asset_type: "document" })
      
      🔴 NEVER guess an asset_id! Always get it fresh from a query.
      
      WHEN SHOWING DOCUMENTS:
      • Found 1 → load_canvas("document_viewer", { asset_id: ID, asset_type: "document" })
      • Found multiple → load_canvas("document_search_results", { query, results })
      • NEVER ask "would you like to see it?" - JUST SHOW IT!

      ═══════════════════════════════════════════════════════════════
      🖼️ CANVAS LOADING - BE PROACTIVE!
      ═══════════════════════════════════════════════════════════════
      
      🔴 ALWAYS LOAD A CANVAS when discussing data - visual > text!
      
      AUTO-LOAD MAPPING (do this WITHOUT being asked):
      ┌─────────────────────────────────────────────────────────────┐
      │ User asks about...        → Load this canvas               │
      ├─────────────────────────────────────────────────────────────┤
      │ Email campaigns           → campaign_viewer                 │
      │ Campaign performance      → analytics_dashboard             │
      │ Landing pages             → landing_page_viewer             │
      │ A specific landing page   → landing_page_editor (with ID)   │
      │ Tasks/work/agents         → scheduled_tasks                 │
      │ Documents                 → document_viewer or search       │
      │ Contacts/CRM data         → analytics_dashboard             │
      │ Analytics/metrics         → analytics_dashboard             │
      │ Installed modules         → module_manager                  │
      │ Module marketplace        → module_marketplace              │
      │ Custom module canvases    → module_<slug>_<canvas>          │
      └─────────────────────────────────────────────────────────────┘
      
      🏭 CUSTOM MODULES & PLATFORM FACTORY:
      When user asks to BUILD new functionality (inventory, project mgmt, etc):
      
      FOR CUSTOM MODULES (interactive design):
      1. Use start_module_design - Ask clarifying questions about what they need
      2. After user answers → propose_module_schema - Show proposed fields/structure
      3. User can request changes → refine_module_schema - Add/remove/modify fields
      4. When approved → approve_module_design - Kicks off the build
      
      FOR TEMPLATES (quick install):
      • Use customize_template if they want to modify a template first
      • Show module_marketplace for browsing: load_canvas("module_marketplace")
      
      FOR EXISTING MODULES:
      • extend_module_schema - Add new fields to installed modules
      • Show module_manager to view installed: load_canvas("module_manager")
      
      EXAMPLES:
      • "How are my email campaigns?" 
        → get_data(campaigns) + load_canvas("campaign_viewer")
      • "Show me landing page performance"
        → get_data(landing_pages) + load_canvas("analytics_dashboard")
      • "What's happening with my tasks?"
        → load_canvas("scheduled_tasks")
      
      STYLE - Be subtle about loading:
      • Load canvases quietly - users see the visual change
      • Check current_canvas first - don't reload if already there
      • DON'T announce it, just present insights with the visual
      
      ❌ "I'll load your campaigns and show you..."
      ✅ "Your Summer Sale campaign has a 42% open rate." (canvas loads automatically)

      ═══════════════════════════════════════════════════════════════
      🤖 AGENT COMMUNICATION
      ═══════════════════════════════════════════════════════════════

      When you see [AGENT: xxx] tags, you're in an EXISTING workflow:
      
      • [REQUEST_TYPE: question] → Relay questions to user conversationally
      • [REQUEST_TYPE: update] → Briefly acknowledge if important
      • [REQUEST_TYPE: completion] → Acknowledge and load relevant canvas
      
      Present agent questions naturally: "For your landing page, what would you like the main headline to be?"

      ═══════════════════════════════════════════════════════════════
      🔍 CONTEXT AWARENESS
      ═══════════════════════════════════════════════════════════════
      
      • "this", "it", "the document" → Refer to CURRENT VIEW
      • On document_viewer: "explain this" = explain the shown document
      • On landing_page_editor: references = the page being edited
      • ALWAYS check CURRENT VIEW before searching for new data
      
      ═══════════════════════════════════════════════════════════════
      ⚠️ GROUNDING - NEVER HALLUCINATE
      ═══════════════════════════════════════════════════════════════

      If you're not sure:
      • web_search to verify facts
      • get_data to check real numbers
      • recall_context to check what was discussed
      • Ask the user for clarification
      
      Being honest about uncertainty > being confidently wrong.
    PROMPT

    # Add agent-specific instructions if using loadout
    if @agent_loadout
      prompt += "\n\n#{@agent_loadout.generate_prompt}"
    end

    # Inject AMOS platform awareness context
    if @amos_integration
      begin
        amos_context = @amos_integration.get_context_injection
        prompt += "\n\n#{amos_context}" if amos_context.present?
      rescue => e
        Rails.logger.debug "[Scout] Could not inject AMOS context: #{e.message}"
      end
    end

    prompt
  end
  
  # Format business context for the system prompt
  def format_business_context_for_prompt
    context_parts = []
    
    # ═══════════════════════════════════════════════════════════════
    # 👤 USER PROFILE
    # ═══════════════════════════════════════════════════════════════
    context_parts << "═══════════════════════════════════════════════════════════════"
    context_parts << "👤 WHO YOU'RE TALKING TO"
    context_parts << "═══════════════════════════════════════════════════════════════"
    
    if @user.present?
      user_name = @user.respond_to?(:full_name) ? @user.full_name : "#{@user.first_name} #{@user.last_name}".strip
      context_parts << "Name: #{user_name}" if user_name.present?
      context_parts << "Email: #{@user.email}" if @user.respond_to?(:email) && @user.email.present?
      context_parts << "Role: #{@user.role.humanize}" if @user.respond_to?(:role) && @user.role.present?
    end
    
    # ═══════════════════════════════════════════════════════════════
    # 🏢 BUSINESS PROFILE
    # ═══════════════════════════════════════════════════════════════
    context_parts << ""
    context_parts << "═══════════════════════════════════════════════════════════════"
    context_parts << "🏢 THEIR BUSINESS"
    context_parts << "═══════════════════════════════════════════════════════════════"
    
    # Try user's business profile first, then entity's
    profile = @user&.business_profile || @entity&.business_profiles&.first
    
    if profile.present?
      context_parts << "Business Name: #{profile.name}" if profile.respond_to?(:name) && profile.name.present?
      context_parts << "Industry: #{profile.industry}" if profile.respond_to?(:industry) && profile.industry.present?
      context_parts << "Website: #{profile.website}" if profile.respond_to?(:website) && profile.website.present?
      context_parts << "Founded: #{profile.founded_year}" if profile.respond_to?(:founded_year) && profile.founded_year.present?
      
      if profile.respond_to?(:description) && profile.description.present?
        context_parts << "Description: #{profile.description.truncate(300)}"
      end
      
      if profile.respond_to?(:target_audience) && profile.target_audience.present?
        context_parts << "Target Audience: #{profile.target_audience}"
      end
      
      if profile.respond_to?(:values) && profile.values.present?
        context_parts << "Core Values: #{profile.values.truncate(200)}"
      end
      
      if profile.respond_to?(:tone_of_voice) && profile.tone_of_voice.present?
        context_parts << "Brand Voice/Tone: #{profile.tone_of_voice.truncate(200)}"
      end
    elsif @entity.present?
      # Fallback to entity info if no business profile
      context_parts << "Business Name: #{@entity.name}"
      context_parts << "Industry: #{@entity.industry}" if @entity.respond_to?(:industry) && @entity.industry.present?
    end
    
    # ═══════════════════════════════════════════════════════════════
    # 📊 ACCOUNT STATS (Quick overview of what they have)
    # ═══════════════════════════════════════════════════════════════
    if @entity.present?
      stats = []
      begin
        campaign_count = @entity.campaigns.count rescue 0
        landing_page_count = @entity.landing_pages.count rescue 0
        contact_count = @entity.contacts.count rescue 0
        template_count = @entity.email_templates.count rescue 0
        
        stats << "#{campaign_count} campaigns" if campaign_count > 0
        stats << "#{landing_page_count} landing pages" if landing_page_count > 0
        stats << "#{contact_count} contacts" if contact_count > 0
        stats << "#{template_count} email templates" if template_count > 0
        
        if stats.any?
          context_parts << ""
          context_parts << "📊 Account Overview: #{stats.join(', ')}"
        end
      rescue => e
        Rails.logger.debug "Could not load account stats: #{e.message}"
      end
      
      # Connected integrations
      begin
        connected = @entity.connections.joins(:integration).where(status: 'connected')
        if connected.any?
          integration_names = connected.includes(:integration).map { |c| c.integration.name }.uniq.first(5)
          context_parts << "🔌 Connected: #{integration_names.join(', ')}"
        end
      rescue => e
        Rails.logger.debug "Could not load integrations: #{e.message}"
      end
    end
    
    # ═══════════════════════════════════════════════════════════════
    # 🧠 LEARNED INSIGHTS (What Scout has learned about this business)
    # ═══════════════════════════════════════════════════════════════
    if @entity.present? && defined?(BusinessInsight)
      begin
        insights = BusinessInsight.where(entity: @entity)
                                  .where("confidence_score >= ?", 0.7)
                                  .order(created_at: :desc)
                                  .limit(5)
        
        if insights.any?
          context_parts << ""
          context_parts << "🧠 What I've Learned About This Business:"
          insights.each do |insight|
            context_parts << "   • #{insight.insight_type.humanize}: #{insight.content.truncate(150)}"
          end
        end
      rescue => e
        Rails.logger.debug "Could not load business insights: #{e.message}"
      end
    end
    
    return "" if context_parts.empty?
    
    <<~CONTEXT
      ═══════════════════════════════════════════════════════════════
      📋 CONTEXT - What you know about this user/business
      ═══════════════════════════════════════════════════════════════
      
      #{context_parts.join("\n")}
    CONTEXT
  end
  
  # Format user memories and preferences for system prompt
  def format_user_memories_for_prompt
    return "" unless @user.present? && @entity.present?
    return "" unless defined?(UserMemory)
    
    begin
      UserMemory.for_prompt(user: @user, entity: @entity, limit: 10)
    rescue => e
      Rails.logger.debug "Could not load user memories: #{e.message}"
      ""
    end
  end
  
  # Format Scout personality for system prompt
  def format_scout_personality_for_prompt
    return "" unless @entity.present?
    return "" unless defined?(ScoutPersonality)
    
    begin
      personality = ScoutPersonality.for_entity(@entity)
      personality&.to_prompt || ""
    rescue => e
      Rails.logger.debug "Could not load Scout personality: #{e.message}"
      ""
    end
  end
  
  # Format Scout's own learnings for system prompt
  def format_scout_learnings_for_prompt
    return "" unless @entity.present?
    return "" unless defined?(ScoutLearning)
    
    begin
      ScoutLearning.for_prompt(entity: @entity, limit: 8)
    rescue => e
      Rails.logger.debug "Could not load Scout learnings: #{e.message}"
      ""
    end
  end
  
  # Format conversation summaries for system prompt
  # This gives Scout context about earlier parts of long conversations
  def format_conversation_summaries_for_prompt
    return "" unless @user.present? && @entity.present?
    
    begin
      # Use unified memory system if available
      if defined?(Scout::UnifiedMemory) && defined?(MemorySegment)
        memory = Scout::UnifiedMemory.new(user: @user, entity: @entity)
        context = memory.build_context
        return memory.format_for_prompt(context)
      end
      
      # Fallback to session-based summaries
      return "" unless @session_id.present? && defined?(ConversationSummary)
      ConversationSummary.for_prompt(session_id: @session_id, limit: 3)
    rescue => e
      Rails.logger.debug "Could not load conversation summaries: #{e.message}"
      ""
    end
  end

  # Format AI rulesets for system prompt injection
  # Rulesets define behavioral constraints that Scout must follow
  def format_ai_rulesets_for_prompt
    return "" unless @entity.present?

    begin
      AiRulesetService.new(@entity).to_system_prompt_section
    rescue => e
      Rails.logger.debug "Could not load AI rulesets: #{e.message}"
      ""
    end
  end

  def format_templates_for_prompt(templates)
    return "None available" if templates.empty?

    templates.map do |t|
      "- #{t[:name]} (#{t[:slug]}): #{t[:description]}"
    end.join("\n      ")
  end

  def handle_streaming_chunk(chunk, accumulated_content, tool_calls, streaming_started, progress_callback)
    case chunk[:type]
    when :content
      accumulated_content << chunk[:content]
      
      # Just stream content as it comes - no complicated word splitting
      progress_callback&.call({
        type: "content_chunk",
        content: chunk[:content]
      })
    when :tool_use_start
      Rails.logger.info "🔧 Tool detected: #{chunk[:tool_name]}"

      # If this is the first tool and no content has been streamed yet,
      # stream some initial feedback so the user knows we're working
      if tool_calls.empty? && accumulated_content.blank?
        # Check if this is a delegation tool
        initial_message = if chunk[:tool_name] == "delegate_to_agent"
          "One moment, let me get the right agent to help with that. "
        else
          "I'll help you with that. "
        end
        accumulated_content << initial_message
        progress_callback&.call({
          type: "content_chunk",
          content: initial_message
        })
      end

      tool_calls << {
        id: chunk[:tool_id],
        name: chunk[:tool_name],
        arguments: ""
      }
      progress_callback&.call({
        type: "tool_start",
        name: chunk[:tool_name]
      })
    when :tool_use
      if tool_calls.any?
        input = chunk[:tool_use].input
        # Handle both Hash and String inputs from streaming
        if input.is_a?(Hash)
          tool_calls.last[:arguments] = input
        elsif input.is_a?(String)
          tool_calls.last[:arguments] += input
        end
      end
    when :usage
      # Token usage with cache metrics and model used (for fallback transparency)
      @model_used = chunk[:model_used] if chunk[:model_used]
      @model_name = chunk[:model_name] if chunk[:model_name]

      progress_callback&.call({
        type: "cache_metrics",
        tokens: chunk[:tokens],
        cache_creation: chunk[:cache_creation] || 0,
        cache_read: chunk[:cache_read] || 0,
        model_used: @model_used,
        model_name: @model_name
      })
    when :message_stop
      # Message complete
      if accumulated_content.present? && !@saved_message_content.include?(accumulated_content.hash)
        progress_callback&.call({
          type: "save_message",
          content: accumulated_content,
          role: "assistant"
        })
        @saved_message_content.add(accumulated_content.hash)
        @messages_saved_during_streaming = true
      end
    end
  end

  def execute_tool_calls(tool_calls, progress_callback)
    results = []

    tool_calls.each do |tool_call|
      begin
        args = parse_tool_arguments(tool_call[:arguments])
        Rails.logger.debug "Executing #{tool_call[:name]} with args: #{args.inspect}"

        result = execute_tool_by_name(tool_call[:name], args, progress_callback)

        # Special handling for delegate_to_agent - display the confirmation message
        if tool_call[:name] == "delegate_to_agent" && result[:success]
          # Stream the helpful delegation message to the user
          if result[:message].present?
            progress_callback&.call({
              type: "content_chunk",
              content: result[:message]
            })
            # Save this as the assistant response
            @delegation_message = result[:message]
          end
          
          # Simplify the result to prevent Scout from adding more
          result = { 
            success: true, 
            agent_name: result[:agent_name],
            note: "Agent is now working on the task."
          }
          # Mark that we should not continue generating content
          @stop_after_delegation = true
        end

        # Special handling for delegate_to_planner
        if tool_call[:name] == "delegate_to_planner" && result[:success] && result[:approval_required]
          # Store flag to indicate workflow delegation happened
          @workflow_delegated = true
          @delegated_task_session_id = result[:task_session_id]
          @delegated_workflow_spec = result[:workflow_spec]
        end

        # Extract sources from tool results
        extract_sources_from_result(tool_call[:name], result)

        progress_callback&.call({
          type: "tool_complete",
          name: tool_call[:name],
          success: result[:success] || false
        })

        Rails.logger.debug "Tool #{tool_call[:name]} result: #{result[:success] ? 'success' : 'failed'}"
        results << result
      rescue JSON::ParserError => e
        Rails.logger.error "Tool execution failed - Invalid JSON: #{e.message}, arguments: #{tool_call[:arguments]}"
        results << { success: false, error: "Invalid tool arguments: #{e.message}" }
      rescue => e
        Rails.logger.error "Tool execution failed: #{e.message}"
        results << { success: false, error: e.message }
      end
    end

    Rails.logger.info "🔧 Tools completed: #{results.map { |r| r[:success] ? '✓' : '✗' }.join(' ')}" if results.any?
    results
  end

  def get_continuation_after_tools(system_prompt, conversation_messages, tool_calls, tool_results, progress_callback)
    # Check if we should stop after delegation
    if @stop_after_delegation
      Rails.logger.info "Stopping response after agent delegation - agent will communicate through Scout"
      return ""
    end
    
    # The tool_use message should already be in conversation_messages
    # Just add the tool results
    Rails.logger.info "Adding tool results for #{tool_calls.length} tool calls"

    # Add tool results (truncated to prevent context overflow)
    conversation_messages << {
      role: "user",
      content: tool_calls.map.with_index do |tool_call, idx|
        {
          type: "tool_result",
          tool_result: {
            tool_use_id: tool_call[:id],
            content: [
              {
                type: "text",
                text: truncate_tool_result(tool_results[idx])
              }
            ]
          }
        }
      end
    }

    # Get continuation
    continuation_message = ""
    continuation_tool_calls = []
    tools = get_filtered_tools

    @ai_service.send_message_streaming(
      system_prompt,
      conversation_messages,
      model: @model,
      max_tokens: 25000,
      temperature: 0.7,
      json_mode: false,
      tools: tools,
      enable_prompt_caching: true
    ) do |chunk|
      case chunk[:type]
      when :content
        continuation_message << chunk[:content]
        Rails.logger.debug "[Scout] Continuation chunk (#{chunk[:content].length} chars): #{chunk[:content][0..20]}..."
        
        # Just stream content as it comes - no complicated word splitting
        progress_callback&.call({
          type: "content_chunk",
          content: chunk[:content]
        })
      when :tool_use_start
        # Handle additional tool calls in continuation
        Rails.logger.info "🔧 Additional tool detected in continuation: #{chunk[:tool_name]}"
        continuation_tool_calls << {
          id: chunk[:tool_id],
          name: chunk[:tool_name],
          arguments: ""
        }
        progress_callback&.call({
          type: "tool_start",
          name: chunk[:tool_name]
        })
      when :tool_use
        if continuation_tool_calls.any? && chunk[:tool_use]
          continuation_tool_calls.last[:arguments] += chunk[:tool_use][:input] || ""
        end
      when :usage
        # Capture model info from continuation as well
        @model_used = chunk[:model_used] if chunk[:model_used]
        @model_name = chunk[:model_name] if chunk[:model_name]
      end
    end

    # If there are more tool calls, execute them recursively
    if continuation_tool_calls.any?
      Rails.logger.info "Executing #{continuation_tool_calls.length} additional tools in continuation"
      additional_results = execute_tool_calls(continuation_tool_calls, progress_callback)

      # Recursively get the next continuation
      return get_continuation_after_tools(
        system_prompt,
        conversation_messages + [
          {
            role: "assistant",
            content: [
              { type: "text", text: continuation_message.present? ? continuation_message : "Continuing with the next step..." }
            ] + continuation_tool_calls.map do |tc|
              {
                type: "tool_use",
                tool_use: {
                  id: tc[:id],
                  name: tc[:name],
                  input: begin
                    parse_tool_arguments(tc[:arguments])
                  rescue JSON::ParserError => e
                    Rails.logger.error "Failed to parse tool arguments: #{tc[:arguments]}"
                    {}
                  end
                }
              }
            end
          },
          {
            role: "user",
            content: continuation_tool_calls.map.with_index do |tc, idx|
              {
                type: "tool_result",
                tool_result: {
                  tool_use_id: tc[:id],
                  content: [
                    {
                      type: "text",
                      text: truncate_tool_result(additional_results[idx])
                    }
                  ]
                }
              }
            end
          }
        ],
        [],  # No more tool calls to add
        [],  # No more results to add
        progress_callback
      )
    end

    response = {
      final_response: {
        message: continuation_message,
        message_already_saved: false,
        delegation_occurred: @stop_after_delegation || false
      },
      tools_used: tool_calls.map { |tc| tc[:name] },
      sources: @sources,
      model_used: @model_used,
      model_name: @model_name,
      delegation_occurred: @stop_after_delegation || false
    }
    
    # Only include canvas info if it wasn't already broadcast
    if @suggested_canvas && !@canvas_already_broadcast
      response[:canvas_type] = @suggested_canvas
      response[:canvas_data] = @canvas_data
    else
      response[:canvas_type] = "conversation"
    end

    # Add workflow approval data if delegation happened
    if @workflow_delegated
      response[:workflow_approval_needed] = true
      response[:task_session_id] = @delegated_task_session_id
      response[:workflow_spec] = @delegated_workflow_spec
    end

    response
  end

  def execute_load_canvas(args, progress_callback = nil)
    canvas_name = args["canvas_name"] || args[:canvas_name]
    canvas_data = args["canvas_data"] || args[:canvas_data] || {}

    # CRITICAL: Send canvas update IMMEDIATELY via progress callback
    # This ensures it arrives BEFORE any response message
    if progress_callback
      # Send the canvas update FIRST - no intermediate message
      progress_callback.call({
        type: "canvas_update",
        canvas_type: canvas_name,
        canvas_data: canvas_data
      })
      
      # Small delay to ensure canvas broadcast completes first
      sleep(0.1)
    end

    # Always set the canvas so it's included in the final response as backup
    safe_load_canvas(canvas_name, canvas_data)
    
    # Mark that we already broadcast this canvas to prevent double broadcast
    @canvas_already_broadcast = true
    
    # Return success
    { success: true, message: nil }
  end

  def safe_load_canvas(canvas_name, data = {})
    if @agent_loadout && !@agent_loadout.canvas_allowed?(canvas_name)
      Rails.logger.warn "Canvas #{canvas_name} not allowed by agent loadout"
      return false
    end

    @suggested_canvas = canvas_name
    @canvas_data = data
    true
  end

  # Broadcast auto-loaded canvas to frontend (before Amos responds)
  def broadcast_auto_canvas(canvas_type, progress_callback)
    return if @canvas_already_broadcast
    return if canvas_type.nil? || canvas_type == :keep_current

    Rails.logger.info "[Scout] Auto-loading canvas: #{canvas_type}"
    
    # Broadcast via progress callback
    progress_callback&.call({
      type: "auto_canvas",
      canvas: canvas_type.to_s,
      message: "Loading #{canvas_type.to_s.humanize}..."
    })

    # Also broadcast via ActionCable for immediate UI update
    if @session_id
      ScoutChannel.broadcast_to(@session_id, {
        type: 'auto_canvas_load',
        canvas: canvas_type.to_s,
        timestamp: Time.current.iso8601
      })
    end

    @canvas_already_broadcast = true
  rescue => e
    Rails.logger.warn "[Scout] Auto-canvas broadcast failed: #{e.message}"
  end

  # Inject canvas context into system prompt (compact, ~30-50 tokens)
  def inject_canvas_context(system_prompt, context_inject)
    return system_prompt if context_inject.blank?

    # Insert at the very beginning for visibility
    <<~PROMPT
      #{context_inject.strip}

      #{system_prompt}
    PROMPT
  end

  def enhance_message_with_canvas_context(message, canvas)
    # Add user context to message (not in cached system prompt for better cache sharing)
    user_name = @user.respond_to?(:first_name) ? "#{@user.first_name} #{@user.last_name}" : @user.to_s
    
    # Use BusinessProfile name if available, otherwise fall back to Entity name
    business_profile = @user&.business_profile || @entity&.business_profiles&.first
    business_name = business_profile&.name.presence || (@entity.respond_to?(:name) ? @entity.name : @entity.to_s)
    
    user_context_prefix = "[User Context: #{user_name} from #{business_name}]\n\n"
    
    # Check for attached files in the context
    enhanced_message = message
    if @context[:attached_files] && @context[:attached_files].any?
      Rails.logger.info "🔍 Found attached files in context: #{@context[:attached_files].inspect}"
      
      file_info = @context[:attached_files].map do |file|
        "📎 #{file['filename'] || file[:filename]} (asset_id: #{file['asset_id'] || file[:asset_id]})"
      end.join("\n")
      
      enhanced_message = "#{message}\n\n[ATTACHED FILES]:\n#{file_info}\n\nIMPORTANT: Use the read_document tool with the asset_id to access these files!"
    end

    # If no canvas, just add user context
    return user_context_prefix + enhanced_message unless canvas.present?

    # Convert ActionController::Parameters to hash if needed
    if canvas.respond_to?(:to_unsafe_h)
      canvas = canvas.to_unsafe_h
    elsif canvas.respond_to?(:to_h) && !canvas.is_a?(String) && !canvas.is_a?(Hash)
      canvas = canvas.to_h
    end

    # Handle both old format (string) and new format (hash with type and data)
    if canvas.is_a?(Hash)
      canvas_type = canvas["type"] || canvas[:type]
      canvas_data = canvas["data"] || canvas[:data] || {}

      # Also convert canvas_data if it's ActionController::Parameters
      if canvas_data.respond_to?(:to_unsafe_h)
        canvas_data = canvas_data.to_unsafe_h
      elsif canvas_data.respond_to?(:to_h) && !canvas_data.is_a?(Hash)
        canvas_data = canvas_data.to_h
      end
    else
      canvas_type = canvas
      canvas_data = {}
    end

    Rails.logger.info "🎨 Canvas context - Type: #{canvas_type}, Data: #{canvas_data.inspect}"

    context_hints = {
      "landing_page_viewer" => "\n[Context: User is viewing landing pages]",
      "landing_page_editor" => lambda { |data|
        landing_page_id = data["landing_page_id"] || data[:landing_page_id]
        Rails.logger.info "📄 Landing page editor - ID: #{landing_page_id}"
        if landing_page_id
          "\n[Context: User is editing landing page ID #{landing_page_id}. Use update_landing_page_content tool to modify this page, not generate_ai_landing_page.]"
        else
          "\n[Context: User is in landing page editor]"
        end
      },
      "document_viewer" => lambda { |data|
        asset_id = data["asset_id"] || data[:asset_id]
        filename = data["filename"] || data[:filename]
        if asset_id
          "\n[Context: User is viewing document '#{filename}' (asset_id: #{asset_id}). When user says 'this' or 'this document', they mean THIS specific document. Use read_document tool with asset_id #{asset_id} to access its content.]"
        else
          "\n[Context: User is viewing a document]"
        end
      },
      "document_search_results" => lambda { |data|
        query = data["query"] || data[:query]
        total = data["total_results"] || data[:total_results]
        "\n[Context: User is viewing document search results for '#{query}' (#{total} results found)]"
      },
      "campaign_viewer" => "\n[Context: User is viewing email campaigns]",
      "email_campaign_viewer" => "\n[Context: User is viewing email campaigns]",
      "contact_viewer" => "\n[Context: User is viewing contacts]",
      "analytics_dashboard" => "\n[Context: User is viewing analytics]",
      "parallel_tasks" => "\n[Context: User is viewing the task monitor]",
      "dynamic_canvas" => lambda { |data|
        title = data["title"] || data[:title] || "dynamic data"
        "\n[Context: User is viewing #{title}]"
      }
    }

    hint = context_hints[canvas_type]
    hint_text = hint.is_a?(Proc) ? hint.call(canvas_data) : hint

    # Add user context prefix + enhanced message (with attached files) + canvas hint
    enhanced = user_context_prefix + enhanced_message + (hint_text || "")
    Rails.logger.info "✅ Enhanced message with user context: #{enhanced}"

    enhanced
  end

  def format_conversation_for_ai(history, current_message)
    Rails.logger.info "🔍 format_conversation_for_ai called with #{history.length} history messages"

    messages = []
    
    # OPTION 1: Extract important IDs/references BEFORE truncation
    working_context = extract_working_context(history)
    
    # OPTION 3: Also retrieve any previously stored context from memory
    # This helps when conversation continues after a gap
    stored_context = retrieve_working_context_from_memory
    if stored_context.any?
      # Merge stored context with current extraction
      stored_context.each do |key, values|
        working_context[key] ||= []
        working_context[key] = (working_context[key] + values).uniq.first(10)
      end
    end
    
    # OPTION 2: Increased from 6 to 12 messages (6 exchanges) for better context retention
    max_messages = 12
    truncated_history = history.last(max_messages)

    if history.length > max_messages
      Rails.logger.info "⚡ Truncated conversation: #{history.length} → #{max_messages} messages"
    end
    
    # Store updated working context in memory for persistence
    store_working_context_in_memory(working_context) if working_context.any?

    # Add working context as first message if we have references from truncated messages
    # OR if we have stored context from a previous session
    needs_context_injection = (working_context.any? && history.length > max_messages) || 
                              (stored_context.any? && history.length < 4)
    
    if needs_context_injection && working_context.any?
      context_text = format_working_context(working_context)
      messages << {
        role: "user",
        content: [{ type: "text", text: "[Working Context - Recent References]\n#{context_text}" }]
      }
      messages << {
        role: "assistant", 
        content: [{ type: "text", text: "I'll keep those references in mind." }]
      }
      Rails.logger.info "📎 Injected working context: #{working_context.keys.join(', ')}"
    end

    # Add recent history, filtering out messages with nil content
    truncated_history.each do |msg|
      content = msg["content"] || msg[:content]
      role = msg["role"] || msg[:role]

      # Skip messages with nil or empty content
      next if content.nil? || content.to_s.strip.empty?

      # Compress long tool-related messages to save tokens, but preserve IDs
      if content.to_s.length > 1000
        content_preview = compress_message_preserve_ids(content.to_s)
        Rails.logger.debug "⚡ Compressed message: #{content.to_s.length} → #{content_preview.length} chars"
      else
        content_preview = content.to_s
      end

      formatted_message = {
        role: role == "user" ? "user" : "assistant",
        content: [{ type: "text", text: content_preview }]
      }

      messages << formatted_message
    end

    # Add current message only if it's not already in the history
    last_user_message = messages.reverse.find { |m| m[:role] == "user" }
    if !last_user_message || last_user_message[:content].first[:text] != current_message
      messages << {
        role: "user",
        content: [{ type: "text", text: current_message }]
      }
    end

    # Log final token estimate
    estimated_tokens = messages.sum { |m| m[:content].first[:text].length / 4 }
    Rails.logger.info "📊 Conversation: #{messages.length} messages, ~#{estimated_tokens} tokens"

    messages
  end

  # OPTION 1: Extract important IDs and references from conversation history before truncation
  def extract_working_context(history)
    context = {
      documents: [],
      campaigns: [],
      landing_pages: [],
      contacts: [],
      agents: []
    }
    
    history.each do |msg|
      content = (msg["content"] || msg[:content]).to_s
      
      # Extract document references (asset_id, rag_document_id, document_id)
      content.scan(/(?:asset_id|rag_document_id|document_id)[:\s]*(\d+)/i).each do |match|
        context[:documents] << match[0].to_i
      end
      
      # Extract document names with IDs from formatted results
      content.scan(/["']([^"']+)["']\s*\((?:id|asset_id)[:\s]*(\d+)/i).each do |name, id|
        context[:documents] << { id: id.to_i, name: name.strip }
      end
      
      # Extract campaign IDs
      content.scan(/campaign[_\s]?id[:\s]*(\d+)/i).each do |match|
        context[:campaigns] << match[0].to_i
      end
      
      # Extract landing page IDs
      content.scan(/landing[_\s]?page[_\s]?id[:\s]*(\d+)/i).each do |match|
        context[:landing_pages] << match[0].to_i
      end
      
      # Extract contact IDs
      content.scan(/contact[_\s]?id[:\s]*(\d+)/i).each do |match|
        context[:contacts] << match[0].to_i
      end
      
      # Extract agent references
      content.scan(/agent[_\s]?(?:type|name)[:\s]*["']?(\w+)["']?/i).each do |match|
        context[:agents] << match[0]
      end
    end
    
    # Deduplicate and clean up
    context.transform_values! do |values|
      values.uniq.first(10) # Keep max 10 of each type
    end
    
    # Remove empty categories
    context.reject! { |_, v| v.empty? }
    
    context
  end
  
  # Format working context for injection into conversation
  def format_working_context(context)
    lines = []
    
    if context[:documents]&.any?
      doc_refs = context[:documents].map do |doc|
        doc.is_a?(Hash) ? "#{doc[:name]} (asset_id: #{doc[:id]})" : "asset_id: #{doc}"
      end
      lines << "📄 Documents: #{doc_refs.join(', ')}"
    end
    
    if context[:campaigns]&.any?
      lines << "📧 Campaigns: #{context[:campaigns].map { |id| "id: #{id}" }.join(', ')}"
    end
    
    if context[:landing_pages]&.any?
      lines << "🌐 Landing Pages: #{context[:landing_pages].map { |id| "id: #{id}" }.join(', ')}"
    end
    
    if context[:contacts]&.any?
      lines << "👤 Contacts: #{context[:contacts].map { |id| "id: #{id}" }.join(', ')}"
    end
    
    if context[:agents]&.any?
      lines << "🤖 Agents: #{context[:agents].join(', ')}"
    end
    
    lines.join("\n")
  end
  
  # OPTION 3: Store working context in unified memory for persistence across truncation
  def store_working_context_in_memory(context)
    return unless @user && @entity && @session_id
    
    begin
      # Store in Redis with session scope for quick access
      redis_key = "scout:working_context:#{@session_id}"
      
      # Merge with existing context (don't overwrite)
      existing = $redis.get(redis_key)
      if existing
        existing_context = JSON.parse(existing, symbolize_names: true) rescue {}
        context.each do |key, values|
          existing_context[key] ||= []
          existing_context[key] = (existing_context[key] + values).uniq.first(10)
        end
        context = existing_context
      end
      
      $redis.setex(redis_key, 1.hour.to_i, context.to_json)
      Rails.logger.debug "📎 Stored working context in memory"
    rescue => e
      Rails.logger.warn "Failed to store working context: #{e.message}"
    end
  end
  
  # Retrieve working context from memory (for use when history is very short)
  def retrieve_working_context_from_memory
    return {} unless @session_id
    
    begin
      redis_key = "scout:working_context:#{@session_id}"
      stored = $redis.get(redis_key)
      return {} unless stored
      
      JSON.parse(stored, symbolize_names: true)
    rescue => e
      Rails.logger.warn "Failed to retrieve working context: #{e.message}"
      {}
    end
  end

  # Compress message content while preserving important IDs and references
  def compress_message_preserve_ids(content)
    # Extract all IDs and references first
    preserved_refs = []
    
    # Preserve document references
    content.scan(/(?:asset_id|rag_document_id|document_id)[:\s]*\d+/i).each do |ref|
      preserved_refs << ref
    end
    
    # Preserve named entities with IDs
    content.scan(/["'][^"']+["']\s*\([^)]*id[^)]*\)/i).each do |ref|
      preserved_refs << ref
    end
    
    # Preserve campaign/landing page/contact IDs
    content.scan(/(?:campaign|landing_page|contact)[_\s]?id[:\s]*\d+/i).each do |ref|
      preserved_refs << ref
    end
    
    # Build compressed version
    # Take first 400 chars of content
    compressed = content.first(400)
    
    # If we have preserved refs that aren't in the first 400 chars, append them
    missing_refs = preserved_refs.reject { |ref| compressed.include?(ref) }
    if missing_refs.any?
      compressed += "... [IDs: #{missing_refs.uniq.join(', ')}]"
    else
      compressed += "... [truncated]" unless content.length <= 400
    end
    
    compressed
  end

  # Extract source information from tool results
  def extract_sources_from_result(tool_name, result)
    return unless result[:success]

    case tool_name
    when "query_document_content"
      # Unified document query - handles both session and RAG sources
      source_type = result[:source] # 'session', 'rag', or 'none'

      if result[:results].is_a?(Array) && result[:results].any?
        result[:results].each do |chunk|
          source_data = {
            tool: "query_document_content"
          }

          # Determine source type from result
          if source_type == 'session'
            source_data[:type] = "session_document"
            source_data[:filename] = chunk[:filename] || chunk.dig(:metadata, :filename)
            source_data[:asset_id] = chunk.dig(:metadata, :asset_id)
          elsif source_type == 'rag'
            source_data[:type] = "rag_document"
            source_data[:filename] = chunk[:filename] || chunk.dig(:metadata, :filename)
            source_data[:page] = chunk.dig(:metadata, :page)
            source_data[:section] = chunk.dig(:metadata, :section)
            source_data[:similarity_score] = chunk[:similarity_score]
          end

          add_source(source_data) if source_data[:filename]
        end
      end

    when "query_rag_store"
      # RAG query tool returns sources array
      if result[:sources].present?
        result[:sources].each do |filename|
          add_source({
            type: "rag_document",
            filename: filename,
            tool: "query_rag_store"
          })
        end
      end

      # Also extract chunk-level details if available
      if result[:results].is_a?(Array)
        result[:results].each do |chunk|
          if chunk[:metadata] && chunk[:metadata][:filename]
            add_source({
              type: "rag_document",
              filename: chunk[:metadata][:filename],
              page: chunk[:metadata][:page],
              section: chunk[:metadata][:section],
              similarity_score: chunk[:similarity_score],
              tool: "query_rag_store"
            })
          end
        end
      end

    when "read_document"
      # Document read tool
      if result[:filename].present?
        add_source({
          type: "document",
          filename: result[:filename],
          asset_id: result[:asset_id],
          content_type: result[:content_type],
          tool: "read_document"
        })
      end

    when "get_data"
      # Data retrieval tool - track what data was fetched
      if result[:records].present?
        add_source({
          type: "database",
          object_type: result[:object_type],
          record_count: result[:record_count],
          tool: "get_data"
        })
      end

    when "web_search_tool"
      # Web search results - track URLs and titles
      if result[:results].is_a?(Array) && result[:results].any?
        result[:results].each do |search_result|
          add_source({
            type: "web_search",
            url: search_result[:url] || search_result["url"],
            title: search_result[:title] || search_result["title"],
            snippet: search_result[:snippet] || search_result["snippet"],
            tool: "web_search_tool"
          })
        end
      end

    when "execute_integration", "invoke_operation"
      # Integration API calls - track which services were used
      add_source({
        type: "integration",
        integration_name: result[:integration_name] || result[:service_name],
        operation: result[:operation] || result[:operation_name],
        record_count: result[:record_count] || result[:results]&.length,
        tool: tool_name
      })

    when "retrieve_history", "search_history"
      # Conversation history - track how many messages were referenced
      if result[:messages].is_a?(Array) && result[:messages].any?
        add_source({
          type: "conversation",
          message_count: result[:messages].length,
          time_range: result[:time_range],
          tool: tool_name
        })
      end

    when "query_metric", "aggregate_artifact_data"
      # Analytics and metrics - track what data was analyzed
      add_source({
        type: "analytics",
        metric_name: result[:metric_name] || result[:artifact_type],
        data_points: result[:data_points]&.length || result[:record_count],
        time_range: result[:time_range],
        tool: tool_name
      })

    when "get_billing_info", "view_invoices"
      # Billing and subscription data
      add_source({
        type: "billing",
        data_type: tool_name == "get_billing_info" ? "Subscription Info" : "Invoices",
        record_count: result[:invoices]&.length || 1,
        tool: tool_name
      })

    when "get_workflow_context"
      # Workflow context - files and data from current workflow
      if result[:files].present? || result[:context_data].present?
        add_source({
          type: "workflow",
          file_count: result[:files]&.length || 0,
          context_keys: result[:context_data]&.keys&.length || 0,
          tool: "get_workflow_context"
        })
      end
    end
  rescue => e
    Rails.logger.error "Error extracting sources: #{e.message}"
  end

  # Add a source to the accumulated sources list
  def add_source(source_data)
    # Deduplicate based on source type
    case source_data[:type]
    when "rag_document", "session_document", "document"
      # For documents, deduplicate by filename
      key = source_data[:filename]
      existing = @sources.find { |s| s[:filename] == key }

      if existing
        # Merge additional details (like page numbers)
        if source_data[:page] && !existing[:pages]&.include?(source_data[:page])
          existing[:pages] ||= []
          existing[:pages] << source_data[:page]
        end
      else
        @sources << source_data
      end

    when "database"
      # For database, deduplicate by object_type
      key = source_data[:object_type]
      existing = @sources.find { |s| s[:type] == "database" && s[:object_type] == key }

      if existing
        # Update record count if new data has more records
        existing[:record_count] = [existing[:record_count], source_data[:record_count]].max
      else
        @sources << source_data
      end

    when "web_search"
      # For web search, deduplicate by URL
      key = source_data[:url]
      existing = @sources.find { |s| s[:type] == "web_search" && s[:url] == key }
      @sources << source_data unless existing

    when "integration"
      # For integrations, deduplicate by integration name + operation
      key = "#{source_data[:integration_name]}_#{source_data[:operation]}"
      existing = @sources.find { |s|
        s[:type] == "integration" &&
        "#{s[:integration_name]}_#{s[:operation]}" == key
      }

      if existing
        # Update record count if available
        existing[:record_count] = [existing[:record_count] || 0, source_data[:record_count] || 0].max
      else
        @sources << source_data
      end

    when "conversation", "analytics", "billing", "workflow"
      # For these types, only add once per type (deduplicate by type)
      existing = @sources.find { |s| s[:type] == source_data[:type] }

      if existing
        # Merge counts and update with latest data
        existing[:message_count] = [existing[:message_count] || 0, source_data[:message_count] || 0].max
        existing[:data_points] = [existing[:data_points] || 0, source_data[:data_points] || 0].max
        existing[:record_count] = [existing[:record_count] || 0, source_data[:record_count] || 0].max
        existing[:file_count] = [existing[:file_count] || 0, source_data[:file_count] || 0].max
      else
        @sources << source_data
      end

    else
      # Unknown type, just add without deduplication
      @sources << source_data
    end
  end
end
