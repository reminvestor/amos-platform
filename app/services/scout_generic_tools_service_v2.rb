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
  end

  def set_context(context = {})
    @context = @context.merge(context)
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

  def process_message_with_tools_streaming(user_message, progress_callback, conversation_history = [], current_canvas = nil)
    @stop_after_delegation = false # Reset flag at start
    @canvas_already_broadcast = false # Reset canvas broadcast flag
    begin
      # Build system prompt
      system_prompt = build_system_prompt(current_canvas)

      # Enhance user message with context
      enhanced_message = enhance_message_with_canvas_context(user_message, current_canvas)

      # Format conversation
      conversation_messages = format_conversation_for_ai(conversation_history, enhanced_message)

      Rails.logger.info "Sending #{conversation_messages.length} messages to #{@ai_provider_name}"
      progress_callback&.call("🤖 Processing request...")

      # Get filtered tools based on agent loadout with tiered discovery
      # Pass the user message to enable RAG-based tool selection
      tools = get_filtered_tools(prompt: user_message)
      Rails.logger.info "Using #{tools.length} tools (filtered by agent loadout + tiered discovery)"

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
              # Parse arguments - handle string, hash, or empty
              input = case tool_call[:arguments]
              when Hash
                        tool_call[:arguments]
              when String
                        tool_call[:arguments].present? ? JSON.parse(tool_call[:arguments]) : {}
              else
                        {}
              end

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

        # If delegation occurred, return appropriate response
        if @stop_after_delegation
          response = {
            final_response: {
              message: "",
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
      
      # Log tool tier breakdown
      stats = scout_config.tool_stats
      Rails.logger.info "🤖 Scout tools: #{stats[:core_count]} core + #{stats[:configured_count]} configured = #{stats[:total_enabled]} total"
    end

    # Get tools from catalog
    tools = @tool_catalog.get_bedrock_tools(
      agent_loadout: @agent_loadout,
      enable_caching: true,
      user: @user,
      entity: @entity,
      prompt: prompt
    )
    
    tiered_enabled = scout_config&.use_tiered_discovery || false
    if tiered_enabled
      Rails.logger.info "🔍 Tiered discovery: ON (may add discovered tools)"
    end

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
    ai_identity = case Rails.application.config.ai_service
    when :bedrock
      "You are Scout (powered by Amos), the AI business assistant."
    else
      "You are Scout, the AI business assistant."
    end

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

    prompt = <<~PROMPT
      #{ai_identity}

      📅 CURRENT DATE/TIME: #{current_datetime}
      
      #{scout_personality}
      
      #{business_context}
      
      #{user_memories}
      
      #{scout_learnings}
      
      #{conversation_summaries}
      
      #{format_current_canvas_for_prompt(current_canvas)}

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

      ═══════════════════════════════════════════════════════════════
      👁️ YOUR NATIVE ABILITIES (always available)
      ═══════════════════════════════════════════════════════════════
      
      SEE & SHOW DATA:
      • get_data - Query contacts, campaigns, landing pages, etc.
      • load_canvas - Display visual interfaces
      • create_dynamic_visualization - Create charts and dashboards
      
      REMEMBER & RECALL:
      • retrieve_history - Get older conversation messages beyond your active window
      • search_history - Find specific topics from past conversation
      
      SEARCH & DISCOVER:
      • web_search - Get real-time information (stocks, weather, news, etc.)
      • query_document_content - Search all uploaded documents
      • read_document - Read specific document content
      
      CONNECT & ORCHESTRATE:
      • list_available_agents - Find specialist agents for tasks
      • delegate_to_agent - Hand off complex work to specialists
      • respond_to_agent - Handle agent questions
      • list_connections - See what integrations are connected
      
      AVAILABLE DATA MODELS: #{available_models.join(', ')}

      ═══════════════════════════════════════════════════════════════
      🧠 CONVERSATION MEMORY - USE IT!
      ═══════════════════════════════════════════════════════════════
      
      You have access to extended conversation history beyond your active window!
      
      WHEN TO USE MEMORY TOOLS:
      • User says "what did I say about X earlier" → search_history(keywords: "X")
      • User says "remind me what we discussed" → retrieve_history(count: 20)
      • User references something not in your recent context → search_history
      • You need context from earlier in a long conversation → retrieve_history
      
      EXAMPLES:
      • "What did I say about the budget?" → search_history(keywords: "budget")
      • "Summarize our first conversation" → retrieve_history(start_index: 1, end_index: 20)
      • "What topics have we covered?" → retrieve_history(count: 50) then summarize
      
      ⚠️ If user references something you don't see in your context, CHECK HISTORY FIRST!

      ═══════════════════════════════════════════════════════════════
      🔴 DECISION FRAMEWORK - FOLLOW THIS ORDER
      ═══════════════════════════════════════════════════════════════
      
      0️⃣ NEED EARLIER CONTEXT?
         • User references past conversation → search_history or retrieve_history
         • "What did I/we say about..." → search_history FIRST
      
      1️⃣ NEED CURRENT/REAL DATA?
         • Stock prices, weather, news → web_search FIRST
         • CRM data, contacts, campaigns → get_data FIRST
         • Documents → query_document_content or read_document FIRST
         • Integration status → list_connections FIRST
         ⚠️ NEVER answer from memory if real-time data exists!
         
      2️⃣ CAN I SHOW/DISPLAY THIS?
         • Show data visually → load_canvas + get_data
         • Create a chart → create_dynamic_visualization
         • Display documents → load_canvas("document_viewer") or load_canvas("document_search_results")
         → USE TOOLS, don't just describe
      
      3️⃣ IS THIS A CREATION/BUILD TASK? → DELEGATE!
         • "Create a landing page" → delegate_to_agent
         • "Build an email campaign" → delegate_to_agent
         • "Connect to Stripe" → delegate_to_agent
         • "Import my contacts" → delegate_to_agent
         → list_available_agents to find the right specialist
         → delegate_to_agent IMMEDIATELY - don't gather requirements yourself
      
      4️⃣ NO AGENT EXISTS? → CREATE ONE!
         • Recurring task with no agent → delegate to agent_architect
         • New integration needed → delegate to integration_architect
         → The platform EVOLVES to meet needs
      
      5️⃣ ONLY THEN: Answer from knowledge

      ═══════════════════════════════════════════════════════════════
      🎨 WHEN TO DELEGATE TO AGENTS (not your job)
      ═══════════════════════════════════════════════════════════════
      
      CONTENT CREATION → Delegate:
      • Landing pages → list_available_agents + delegate_to_agent
      • Email campaigns → delegate_to_agent
      • Blog posts, marketing content → delegate_to_agent
      
      BUILDING & INTEGRATION → Delegate:
      • Connect to Stripe/APIs → delegate_to_agent
      • Build workflows → delegate_to_agent
      • Create new tools → delegate_to_agent
      
      DATA OPERATIONS → Delegate:
      • Import contacts from CSV → delegate_to_agent
      • Data migration → delegate_to_agent
      
      DELEGATION FLOW:
      1. Say "One moment, let me get the right specialist..."
      2. Call list_available_agents(task_description: "detailed description")
      3. Call delegate_to_agent with the best agent
      4. Stay silent - the agent will communicate through you
      
      🔴 DO NOT gather requirements yourself! Let the agent ask its own questions.
      
      WRONG: "To create this, I need to know: 1. What's your product?"
      RIGHT: "Let me get our landing page specialist on that!" → delegate_to_agent

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
      
      WHEN SHOWING DOCUMENTS:
      • Found 1 → load_canvas("document_viewer", { asset_id: ID })
      • Found multiple → load_canvas("document_search_results", { query, results })
      • NEVER ask "would you like to see it?" - JUST SHOW IT!

      ═══════════════════════════════════════════════════════════════
      🖼️ CANVAS LOADING - BE SUBTLE
      ═══════════════════════════════════════════════════════════════

      • Load canvases quietly - users see the visual change
      • Check current_canvas first - don't reload if already there
      • DON'T say "I've loaded..." or "Let me show you..."
      • Just present the data/insights directly
      
      ❌ "I'll load your campaigns and show you..."
      ✅ "Your Summer Sale campaign has a 42% open rate."

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
      • search_history to check what was discussed
      • Ask the user for clarification
      
      Being honest about uncertainty > being confidently wrong.
    PROMPT

    # Add agent-specific instructions if using loadout
    if @agent_loadout
      prompt += "\n\n#{@agent_loadout.generate_prompt}"
    end

    prompt
  end
  
  # Format business context for the system prompt
  def format_business_context_for_prompt
    context_parts = []
    
    # User info
    user_name = @user.respond_to?(:first_name) ? "#{@user.first_name} #{@user.last_name}".strip : nil
    context_parts << "👤 USER: #{user_name}" if user_name.present?
    
    # Entity info
    if @entity.present?
      context_parts << "🏢 BUSINESS: #{@entity.name}"
      context_parts << "   Industry: #{@entity.industry}" if @entity.respond_to?(:industry) && @entity.industry.present?
    end
    
    # Business profile
    if @entity.present? && @entity.respond_to?(:business_profiles)
      profile = @entity.business_profiles&.first
      if profile.present?
        if profile.respond_to?(:target_audience) && profile.target_audience.present?
          context_parts << "   Target Audience: #{profile.target_audience}"
        end
        if profile.respond_to?(:business_description) && profile.business_description.present?
          context_parts << "   Description: #{profile.business_description.truncate(100)}"
        end
      end
    end
    
    # Recent business insights (learned facts)
    if @entity.present? && defined?(BusinessInsight)
      begin
        insights = BusinessInsight.where(entity: @entity)
                                  .where("confidence_score >= ?", 0.7)
                                  .order(created_at: :desc)
                                  .limit(5)
        
        if insights.any?
          context_parts << "\n📊 LEARNED ABOUT THIS BUSINESS:"
          insights.each do |insight|
            context_parts << "   • #{insight.insight_type.humanize}: #{insight.content.truncate(100)}"
          end
        end
      rescue => e
        Rails.logger.debug "Could not load business insights: #{e.message}"
      end
    end
    
    # Integration status summary
    if @entity.present?
      begin
        connected_integrations = @entity.connections.joins(:integration).where(status: 'connected').count
        if connected_integrations > 0
          context_parts << "\n🔌 CONNECTED INTEGRATIONS: #{connected_integrations}"
        end
      rescue => e
        Rails.logger.debug "Could not load integration count: #{e.message}"
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
    return "" unless @session_id.present?
    return "" unless defined?(ConversationSummary)
    
    begin
      ConversationSummary.for_prompt(session_id: @session_id, limit: 3)
    rescue => e
      Rails.logger.debug "Could not load conversation summaries: #{e.message}"
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
        args = case tool_call[:arguments]
        when Hash
                 tool_call[:arguments]
        when String
                 tool_call[:arguments].present? ? JSON.parse(tool_call[:arguments]) : {}
        else
                 {}
        end
        Rails.logger.info "Executing #{tool_call[:name]} with args: #{args.inspect}"

        result = execute_tool_by_name(tool_call[:name], args, progress_callback)

        # Special handling for delegate_to_agent - minimize response
        if tool_call[:name] == "delegate_to_agent" && result[:success]
          # Simplify the result to prevent Scout from mentioning delegation details
          result = { 
            success: true, 
            note: "Processing..." 
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

        Rails.logger.info "Tool #{tool_call[:name]} result: #{result.inspect}"
        results << result
      rescue JSON::ParserError => e
        Rails.logger.error "Tool execution failed - Invalid JSON: #{e.message}, arguments: #{tool_call[:arguments]}"
        results << { success: false, error: "Invalid tool arguments: #{e.message}" }
      rescue => e
        Rails.logger.error "Tool execution failed: #{e.message}"
        results << { success: false, error: e.message }
      end
    end

    Rails.logger.info "All tool results: #{results.inspect}"
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
                    tc[:arguments].present? ? JSON.parse(tc[:arguments]) : {}
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

  def enhance_message_with_canvas_context(message, canvas)
    # Add user context to message (not in cached system prompt for better cache sharing)
    user_name = @user.respond_to?(:first_name) ? "#{@user.first_name} #{@user.last_name}" : @user.to_s
    entity_name = @entity.respond_to?(:name) ? @entity.name : @entity.to_s
    user_context_prefix = "[User Context: #{user_name} from #{entity_name}]\n\n"
    
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
    Rails.logger.info "🔍 Current message: #{current_message}"

    messages = []

    # Truncate to last 6 messages (3 exchanges) for performance
    # This prevents token bloat as conversation grows
    truncated_history = history.last(6)

    if history.length > 6
      Rails.logger.info "⚡ Truncated conversation history: #{history.length} → 6 messages (saved ~#{(history.length - 6) * 500} tokens)"
    end

    # Add recent history, filtering out messages with nil content
    truncated_history.each do |msg|
      content = msg["content"] || msg[:content]
      role = msg["role"] || msg[:role]

      # Skip messages with nil or empty content
      next if content.nil? || content.to_s.strip.empty?

      # Compress long tool-related messages to save tokens
      if content.to_s.length > 1000
        content_preview = content.to_s.first(500) + "... [truncated for performance]"
        Rails.logger.info "⚡ Compressed long message: #{content.to_s.length} → 500 chars"
      else
        content_preview = content.to_s
      end

      formatted_message = {
        role: role == "user" ? "user" : "assistant",
        content: [ { type: "text", text: content_preview } ]
      }

      Rails.logger.info "🔍 Adding history message: role=#{role}, content=#{content_preview.first(50)}..."

      messages << formatted_message
    end

    # Add current message only if it's not already in the history
    last_user_message = messages.reverse.find { |m| m[:role] == "user" }
    if !last_user_message || last_user_message[:content].first[:text] != current_message
      Rails.logger.info "🔍 Adding current message as it's not in history"
      messages << {
        role: "user",
        content: [ { type: "text", text: current_message } ]
      }
    else
      Rails.logger.info "🔍 Current message already in history, not adding again"
    end

    # Log final token estimate
    estimated_tokens = messages.sum { |m| m[:content].first[:text].length / 4 }
    Rails.logger.info "📊 Conversation messages: #{messages.length}, estimated ~#{estimated_tokens} tokens"

    messages
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
