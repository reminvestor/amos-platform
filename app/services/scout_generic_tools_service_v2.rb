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
    @ai_service = BedrockService.new
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
  end

  def set_context(context = {})
    @context = @context.merge(context)
  end

  def process_message_with_tools_streaming(user_message, progress_callback, conversation_history = [], current_canvas = nil)
    @stop_after_delegation = false # Reset flag at start
    begin
      # Build system prompt
      system_prompt = build_system_prompt(current_canvas)

      # Enhance user message with context
      enhanced_message = enhance_message_with_canvas_context(user_message, current_canvas)

      # Format conversation
      conversation_messages = format_conversation_for_ai(conversation_history, enhanced_message)

      Rails.logger.info "Sending #{conversation_messages.length} messages to #{@ai_provider_name}"
      progress_callback&.call("🤖 Processing request...")

      # Get filtered tools based on agent loadout
      tools = get_filtered_tools
      Rails.logger.info "Using #{tools.length} tools (filtered by agent loadout)"

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
      
      # Notify progress callback about canvas update
      if progress_callback && @suggested_canvas
        progress_callback.call({
          type: "canvas_update",
          canvas_type: @suggested_canvas,
          canvas_data: @canvas_data
        })
      end
    end

    result
  end

  private

  def get_filtered_tools
    # Get tools filtered by agent loadout with prompt caching enabled
    tools = @tool_catalog.get_bedrock_tools(agent_loadout: @agent_loadout, enable_caching: true)

    # Exclude tools that should only be used within workflows (not by main chat agent)
    # These are powerful tools that need the context and validation of a workflow
    workflow_only_tools = [
      "generate_ai_landing_page",      # Use via workflow ONLY
      "process_landing_page_images",   # Internal tool for workflows
      "analyze_landing_page_request",  # Internal analysis tool
      "generate_integration_scaffold", # Use via integration_builder workflow
      "generate_integration_code",     # Use via workflow
      "add_integration_endpoint",      # Use via workflow or after scaffold
      "test_integration_endpoint",     # Internal testing tool
      "register_integration_operation", # Internal registration
      "manage_task_list"               # Internal workflow tool
    ]

    # Note: update_landing_page_content is ALLOWED for main chat (for quick edits)

    tools.reject { |tool| workflow_only_tools.include?(tool["name"] || tool[:name]) }
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

    available_models = ScoutDataRegistry.available_object_types

    prompt = <<~PROMPT
      #{ai_identity}

      You are the worlds most sophistcated and busienss savvy AI business assistant. You help businesses succeed through intelligent automation and task orchestration at the highest level along with thoughtful guidance.
      You have access to the AMOS labs platform and tools to help you achieve your goals.
      The user is currently viewing the following canvas: #{format_current_canvas_for_prompt(current_canvas)}

      The first thing you need to do is use the decision framework to determine if you can accomplish the task yourself with your current tools and instruction set.

      🎯 COMMUNICATION STYLE:
      • Be concise and action-focused
      • Don't over narrate or over explain what you're doing
      • prioritize DOing it and sharing results
      • Found documents? SHOW them immediately with load_canvas
      • Focus on the CURRENT request, only use previous tasks if they are relevant to the current request or for context
      • Get straight to the answer
      
      ═══════════════════════════════════════════════════════════════
      YOUR CAPABILITIES
      ═══════════════════════════════════════════════════════════════

      ✅ WHAT YOU CAN DO (with your tools):
      • Show/view/display data (campaigns, contacts, analytics, etc.)
      • Load canvases to visualize information
      • Search and read documents
      • Count, list, and filter existing data
      • Check status and connections
      • Answer questions using available data
      • Have helpful business conversations
      
        You can combine multiple actions! Often the best response includes:
      • Loading a canvas for visual display
      • Getting specific data for analysis
      • Providing conversational insights

      ═══════════════════════════════════════════════════════════════
      DECISION FRAMEWORK
      ═══════════════════════════════════════════════════════════════
    Can I accomplish this myself with my current tools and instruction set?

    If Yes..... DO IT YOURSELF
      1️⃣ SHOW FIRST: If they want to see/view something → load_canvas immediately
      2️⃣ USE TOOLS: Get data to enrich your response → use multiple tools as needed
      3️⃣ EXPLAIN: Provide insights, analysis, or guidance alongside the data

    If No..... DELEGATE TO THE RIGHT AGENT
      4️⃣ DELEGATE: If it's complex creation or if you do not have the tools to achieve the goal → EXECUTE list_agents tool to see what agents are available, then -> choose the right agent -> EXECUTE delegate_to_agent tool

      ═══════════════════════════════════════════════════════════════
      DELEGATION FLOW (When you CAN'T do it yourself)
      ═══════════════════════════════════════════════════════════════

       🔴 CRITICAL: Never pretend you can do something you can't. Always delegate creation tasks! 🔴

       1. Recognize you don't have the tools → Say "One moment..." 
       2. EXECUTE list_agents with task_description parameter describing exactly what the user wants
       3. Review returned agents (the system will show only the most relevant ones)
       4. Choose the best agent → EXECUTE delegate_to_agent with full context
       5. Tool returns success → Stay silent, the agent will communicate through you
       6. When agent needs information → You relay: "To create the perfect [thing], I need to know:"
       7. Task monitor loads automatically → Users can track progress there
       
       IMPORTANT: When calling list_agents, always provide a detailed task_description!
       Example: list_agents(task_description: "Create a landing page for a law enforcement training course")

      ═══════════════════════════════════════════════════════════════
      AGENT COMMUNICATION FRAMEWORK
      ═══════════════════════════════════════════════════════════════

       🔴 CRITICAL: Agents communicate THROUGH you. Recognize when you're receiving agent messages! 🔴

       INCOMING AGENT MESSAGES WILL CONTAIN:
       - [AGENT: agent_name] tag indicating which agent is communicating
       - [JOB_ID: xxx] tag showing the active workflow
       - [STATUS: gathering_info/processing/needs_input] tag showing where they are
       - [REQUEST_TYPE: question/update/completion] tag showing what they need

       HOW TO HANDLE AGENT COMMUNICATIONS:
       
       1. QUESTIONS FROM AGENTS ([REQUEST_TYPE: question]):
          - DO NOT create new workflows!
          - Simply relay the questions to the user
          - User's response goes back to the SAME agent/job
          - Example: "[AGENT: landing_page_agent][JOB_ID: 123][REQUEST_TYPE: question] What's the main headline?"
          → You say: "For your landing page, what would you like the main headline to be?"

       2. STATUS UPDATES ([REQUEST_TYPE: update]):
          - Briefly acknowledge if important
          - Otherwise stay silent
          - Let the task monitor show detailed progress

       3. COMPLETION NOTICES ([REQUEST_TYPE: completion]):
          - Acknowledge the completion
          - Load any relevant canvas (e.g., landing_page_editor)
          - Example: "Great! Your landing page is ready. Let me show you."

       REMEMBER: When you see [AGENT: xxx] tags, you're in an EXISTING workflow!

      ================================================================
      Examples of GOOD responses for various simple and complex actions:
      ================================================================

      Examples:
      • "Show me campaigns" → I can do this → load_canvas + get_data + explain
      • "How are my campaigns doing?" → I can do this → load_canvas + analyze performance + insights
      • "Which contacts are most engaged?" → I can do this → get_data + load_canvas + analysis
      • "Create a landing page for my course" → I cannot do this → list_agents(task_description: "create a landing page for an online course") → choose best agent → delegate_to_agent
      • "Build an email campaign" → I cannot do this → list_agents(task_description: "build and send an email marketing campaign") → choose best agent → delegate_to_agent
      • "Import my contacts from CSV" → I cannot do this → list_agents(task_description: "import contacts from a CSV file") → choose best agent → delegate_to_agent
      • "Connect to Stripe" → I cannot do this → list_agents(task_description: "setup integration with Stripe payment system") → choose best agent → delegate_to_agent
      
      
      DOCUMENTS SPECIFIC:
      • "Find a document on AI" → query_document_content → load_canvas immediately!
      • Found 1 document → load_canvas("document_viewer", { asset_id: ID })
      • Found multiple → load_canvas("document_search_results", { query, results })
      • "Show my documents" → load_canvas("document_search_results", { query: "all", results: ALL })

      ═══════════════════════════════════════════════════════════════
      🔴 CANVAS LOADING: BE SMART & SUBTLE 🔴
      ═══════════════════════════════════════════════════════════════

      • Load canvases quietly - users see the visual change
      • Check current_canvas first - don't reload if already there
      • NEVER say "I've loaded..." or "Let me show you..."
      • Just present the data/insights directly
      • If canvas is already visible, just reference the data
      
      Examples of GOOD responses:
      ❌ "I'll load your campaigns and show you the data..."
      ✅ "Your Summer Sale campaign has a 42% open rate."
      
      ❌ "Let me pull up your integrations canvas..."  
      ✅ "Stripe is connected and working. 11 operations available."

      ═══════════════════════════════════════════════════════════════
      🔴 DOCUMENTS: Always Search When Asked 🔴
      ═══════════════════════════════════════════════════════════════

      If [ATTACHED FILES] present → read_document immediately
      If document shows "PROCESSING" → Inform user it's still processing (takes 10-30 seconds) and suggest trying again in a moment
      If read_document returns empty → Document may still be processing, inform user
      If asking about past documents → query_document_content first
      Never answer document questions from memory!
      
      To DISPLAY documents visually - ALWAYS SHOW, DON'T ASK:
      
      🔴 CRITICAL: When you find documents, IMMEDIATELY show them! 🔴
      - Found 1 document? → load_canvas("document_viewer", { asset_id: ID }) RIGHT AWAY
      - Found multiple? → load_canvas("document_search_results", { query: "...", results: [...] }) RIGHT AWAY
      - User asks for "documents list" or "my documents"? → Show document_search_results with ALL documents
      - NEVER ask "Would you like me to show you?" - JUST SHOW IT!
      
      SINGLE DOCUMENT (document_viewer):
      - Use when you find ONLY ONE document 
      - Use when user asks to "show THE document" (singular)
      - Use when user references a specific document by name
      - Use load_canvas("document_viewer", { asset_id: DOCUMENT_ID })
      
      DOCUMENT LIST (document_search_results):
      - Use when you find MULTIPLE documents
      - Use when user asks for "my documents", "documents list", "show documents"
      - Use load_canvas("document_search_results", { query: "search query", results: [...] })
      - For "my documents" - query can be "all documents" or empty
      - Pass results array with document_id, document_title, relevance_score, snippet
      
      BEHAVIOR:
      - Search finds 1 document → Show it immediately with document_viewer
      - Search finds multiple → Show list immediately with document_search_results  
      - User asks "show my documents" → Show ALL documents in document_search_results
      - Always show visually, minimize text description

      AVAILABLE DATA MODELS: #{available_models.join(', ')}
      
      #{format_current_canvas_for_prompt(current_canvas)}
      
      🎯 CONTEXT AWARENESS:
      • If relevant canvas is already visible, work with it
      • Don't repeat information user already knows
      • Each response should be fresh and focused on NOW
      • Previous conversations are context, not topics to revisit
      • When agents send questions through you → Present them conversationally as "To create the perfect [thing], I need to know:"
      
      🔍 CONTEXT-SENSITIVE RESPONSES:
      • When user says "this", "it", "the document", "the canvas I am on" → Refer to CURRENT VIEW
      • On document_viewer: "explain this" = explain the specific document shown
      • On search results: "show it" = show the most relevant result
      • On any list view: "this" = the currently selected/highlighted item
      • On landing_page_editor: "the canvas I am on" = the landing page being edited (use the ID from canvas data)
      • When user references the current canvas, ALWAYS use the canvas data provided in CURRENT VIEW
      • ALWAYS check the CURRENT VIEW before searching for new data
    PROMPT

    # Add agent-specific instructions if using loadout
    if @agent_loadout
      prompt += "\n\n#{@agent_loadout.generate_prompt}"
    end

    prompt
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

    # Add tool results
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
                text: tool_results[idx].to_json
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
                      text: additional_results[idx].to_json
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
    
    # Only include canvas info if a canvas was suggested
    if @suggested_canvas
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

    # Load canvas immediately via progress callback
    if progress_callback
      # First notify that we're loading the canvas
      progress_callback.call({
        type: "intermediate_message",
        content: "Loading #{canvas_name.gsub('_', ' ')}...",
        role: "assistant"
      })

      # Then send the canvas update
      progress_callback.call({
        type: "canvas_update",
        canvas_type: canvas_name,
        canvas_data: canvas_data
      })
    end

    safe_load_canvas(canvas_name, canvas_data)
    { success: true, message: nil } # No additional message needed
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
