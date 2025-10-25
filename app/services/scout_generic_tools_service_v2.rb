class ScoutGenericToolsServiceV2
  attr_reader :user, :entity, :session_id, :agent_loadout
  attr_accessor :suggested_canvas, :canvas_data

  def initialize(user, entity, session_id, agent_loadout: nil)
    @user = user
    @entity = entity
    @session_id = session_id
    @agent_loadout = agent_loadout
    @ai_service = BedrockService.new
    @ai_provider_name = Rails.application.config.ai_service.to_s.capitalize
    @tool_catalog = Tools::ToolCatalog.instance
    @suggested_canvas = nil
    @canvas_data = {}
    @saved_message_content = Set.new
    @messages_saved_during_streaming = false
    @context = {}
  end

  def set_context(context = {})
    @context = @context.merge(context)
  end

  def process_message_with_tools_streaming(user_message, progress_callback, conversation_history = [], current_canvas = nil)
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

        final_response
      else
        # No tools used, return the accumulated content
        {
          final_response: {
            message: accumulated_content,
            message_already_saved: @messages_saved_during_streaming
          },
          canvas_type: @suggested_canvas || "conversation",
          canvas_data: @canvas_data,
          tools_used: []
        }
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
      context: tool_context
    )

    # Handle any canvas suggestions from tools
    if tool_context[:canvas_suggestion]
      safe_load_canvas(tool_context[:canvas_suggestion], tool_context[:canvas_data] || {})
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

  def build_system_prompt(current_canvas = nil)
    ai_identity = case Rails.application.config.ai_service
    when :bedrock
      "You are Amos, the AI business automation assistant powered by AMOS Labs."
    else
      "You are Amos, the AI business automation assistant."
    end

    available_models = ScoutDataRegistry.available_object_types

    # Get available workflow templates
    available_templates = WorkflowTemplateLoader.list_all_templates

    prompt = <<~PROMPT
      #{ai_identity}

      DATA MODELS: #{available_models.join(', ')}

      WORKFLOW TEMPLATES:
      #{format_templates_for_prompt(available_templates)}
      Use get_template_details(slug) for details. Planner selects best template when you delegate.

      CONVERSATION HISTORY:
      If user references earlier conversation not in your context:
      - get_message_count: See total messages
      - retrieve_history(count): Get older messages
      - search_history(keywords): Find specific content

      DELEGATION RULES:
      When calling delegate_to_planner, your response should ONLY:
      1. Acknowledge briefly (1 sentence)
      2. Call the tool
      3. STOP

      DO NOT ask for requirements/preferences - workflow gathers that conversationally.
      ✅ Good: "I'll create that landing page." [calls delegate_to_planner]
      ❌ Bad: "What's your value proposition? Target audience?" [workflow will ask!]

      CANVAS LOADING:
      Always load canvas FIRST, then explain what's shown.
      - "campaigns" → load_canvas("campaign_viewer")
      - "landing pages" → load_canvas("landing_page_viewer")
      - "contacts" → load_canvas("contact_viewer")
      - "integrations" → load_canvas("integrations_manager")
      - "analytics" → load_canvas("analytics_dashboard")

      DOCUMENT HANDLING:
      When user uploads file (PDF, DOCX) and asks about it:
      1. ALWAYS read_document(asset_id) first to extract content
      2. Then perform task (translate, summarize, analyze)

      ❌ WRONG: Search web based on filename
      ✅ RIGHT: read_document to get actual content

      Example: "Translate this PDF" → read_document(asset_id) → translate extracted text

      LANDING PAGE OPERATIONS:
      Detect intent - edit existing vs create new:
      - "update"/"change"/"modify" → update_landing_page_content
      - "create"/"build"/"make" → delegate_to_planner(landing_page_creation_v2)
      - NEVER call generate_ai_landing_page directly (always via workflow)

      CREATING OBJECTS:
      Before using create_object, ALWAYS:
      1. get_schema(object_type) to see valid fields
      2. Check creation_notes for metadata field usage
      3. Then call create_object with correct structure

      Example: get_schema("contact") shows address/company go in metadata, not top-level.

      SUBSCRIPTIONS - CRITICAL:
      MUST call actual tools - NEVER fake responses.

      ❌ WRONG: "Your subscription has been upgraded" (without calling tool)
      ✅ CORRECT: Call update_subscription, wait for result, confirm based on actual response

      Tools:
      - update_subscription(plan_tier): Change plan
      - cancel_subscription(confirm:true): Cancel
      - get_billing_info: View details

      If tool fails, report error honestly - don't pretend it worked.

      INTEGRATIONS:
      Simple: execute_integration(integration: "stripe", operation: "list_customers", params: {})
      Discovery: list_connections, list_operations(integration_slug: "stripe")
      Building NEW integrations: delegate_to_planner (uses integration_builder_v2)

      For existing integrations:
      1. list_connections to find service
      2. list_operations(integration_slug) to see available operations
      3. invoke_operation or execute_integration to run

      REQUEST ROUTING - You are an orchestrator:

      SIMPLE REQUESTS (use tools directly):
      - Data queries: get_data(object_type: "campaigns")
      - Simple creation: get_schema → create_object
      - Simple updates: update_object
      - Integration calls: execute_integration
      - Analysis: aggregate_artifact_data, create_dynamic_visualization

      COMPLEX REQUESTS (delegate to planner):
      - Multi-step tasks (email campaigns, product launches)
      - Content generation (landing pages, email templates)
      - Integration building (new API connections)
      - Tasks needing user input/creative decisions

      Workflows have specialized executors with proper tool scoping - trust the system.
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
      progress_callback&.call({
        type: "content_chunk",
        content: chunk[:content]
      })
    when :tool_use_start
      Rails.logger.info "🔧 Tool detected: #{chunk[:tool_name]}"

      # If this is the first tool and no content has been streamed yet,
      # stream some initial feedback so the user knows we're working
      if tool_calls.empty? && accumulated_content.blank?
        initial_message = "I'll help you with that. "
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
      # Token usage with cache metrics
      progress_callback&.call({
        type: "cache_metrics",
        tokens: chunk[:tokens],
        cache_creation: chunk[:cache_creation] || 0,
        cache_read: chunk[:cache_read] || 0
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

        # Special handling for delegate_to_planner
        if tool_call[:name] == "delegate_to_planner" && result[:success] && result[:approval_required]
          # Store flag to indicate workflow delegation happened
          @workflow_delegated = true
          @delegated_task_session_id = result[:task_session_id]
          @delegated_workflow_spec = result[:workflow_spec]
        end

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
      max_tokens: 25000,
      temperature: 0.7,
      json_mode: false,
      tools: tools,
      enable_prompt_caching: true
    ) do |chunk|
      case chunk[:type]
      when :content
        continuation_message << chunk[:content]
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
        message_already_saved: false
      },
      canvas_type: @suggested_canvas || "conversation",
      canvas_data: @canvas_data,
      tools_used: tool_calls.map { |tc| tc[:name] }
    }

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

    # If no canvas, just add user context
    return user_context_prefix + message unless canvas.present?

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
      "campaign_viewer" => "\n[Context: User is viewing email campaigns]",
      "contact_viewer" => "\n[Context: User is viewing contacts]",
      "analytics_dashboard" => "\n[Context: User is viewing analytics]"
    }

    hint = context_hints[canvas_type]
    hint_text = hint.is_a?(Proc) ? hint.call(canvas_data) : hint

    # Add user context prefix + message + canvas hint
    enhanced = user_context_prefix + message + (hint_text || "")
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
end
