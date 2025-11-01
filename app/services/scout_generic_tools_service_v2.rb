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
          tools_used: [],
          sources: @sources,
          model_used: @model_used,
          model_name: @model_name
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

      ═══════════════════════════════════════════════════════════════
      🔴 CRITICAL: DOCUMENT SEARCH PRIORITY 🔴
      ═══════════════════════════════════════════════════════════════

      When users ask questions about information in documents they've uploaded:

      YOU MUST CALL query_document_content FIRST! Do not answer from memory!

      Triggers (MUST use query_document_content):
      - "tell me about X" → query_document_content(query: "X")
      - "summarize my data for X" → query_document_content(query: "X")
      - "what do I have about X" → query_document_content(query: "X")
      - "find information on X" → query_document_content(query: "X")
      - "search my documents for X" → query_document_content(query: "X")

      This tool is SMART:
      1. Checks recent uploads first (session storage - instant, free)
      2. Falls back to permanent knowledge base (RAG - comprehensive)

      NEVER say "based on searching" unless you ACTUALLY called query_document_content!
      NEVER answer from conversation memory - ALWAYS query documents first!

      ═══════════════════════════════════════════════════════════════

      You have access to a comprehensive toolset for managing and automating business operations.

      CONVERSATION HISTORY:
      You have access to the last 20 messages in your active context window. If the user references
      something from earlier in the conversation that you don't see in your current context, you can:
      - Use get_message_count to see how many total messages exist
      - Use retrieve_history to get older messages by index range or count
      - Use search_history to find messages containing specific keywords

      Example: If user says "What did I say about the budget earlier?" and you don't see budget
      discussions in your recent messages, use search_history(keywords: "budget") to find them.

      AVAILABLE DATA MODELS: #{available_models.join(', ')}

      AVAILABLE WORKFLOW TEMPLATES:
      You have access to pre-built intelligent workflow templates. When a user request matches#{' '}
      one of these templates, the system can handle it with advanced capabilities like:
      - Analyzing uploaded files to extract requirements
      - Conversational data gathering (no forms)
      - Adaptive execution with self-healing

      Templates Available:
      #{format_templates_for_prompt(available_templates)}

      To learn more about a template, use the get_template_details tool with the template slug.
      The planner will intelligently select the best template when you delegate complex requests.

      CRITICAL DELEGATION RULE:
      When you call delegate_to_planner, your response should ONLY:
      1. Briefly acknowledge the request (1 sentence max)
      2. Call the tool
      3. STOP - do not say anything else

      DO NOT:
      ❌ Ask questions about requirements
      ❌ List what information you need
      ❌ Explain what the workflow will do
      ❌ Ask for design preferences or details

      The workflow itself will ask for everything needed conversationally.

      Good example:
      "I'll create that landing page for you." [calls delegate_to_planner] [STOPS]

      Bad example:
      "I'll create a landing page! Let me gather some information. What is your value proposition? Who is your target audience?" [This is wrong - the workflow will ask this!]

      INTELLIGENT CANVAS:
      IMPORTANT: When users ask to see/view/show campaigns, landing pages, contacts, or any data:
      1. IMMEDIATELY use the load_canvas tool to display the appropriate viewer
      2. Then provide additional insights or help with the data shown

      Canvas mappings:
      - "show campaigns" or "campaigns" → load_canvas with canvas_name: "campaign_viewer"
      - "show landing pages" or "landing pages" → load_canvas with canvas_name: "landing_page_viewer"
      - "show contacts" or "contacts" → load_canvas with canvas_name: "contact_viewer"

      🔴 DOCUMENT HANDLING - TWO DIFFERENT SITUATIONS:

      ═══════════════════════════════════════════════════════════════════════════════
      SITUATION 1: User JUST uploaded a file in THIS message (has asset_id in context)
      ═══════════════════════════════════════════════════════════════════════════════
      → Use read_document(asset_id: X) to read the NEWLY uploaded file

      STEP 1: ALWAYS read the document first!
      - Use read_document tool with the asset_id from attached files
      - This extracts the actual text content

      STEP 2: Then perform the requested task
      - Translate: Read document → translate the extracted text
      - Summarize: Read document → summarize the content
      - Analyze: Read document → analyze the content
      - Answer questions: Read document → answer based on content

      FILE INFO: Check for attached_files in context - they have asset_id and filename

      WRONG: Searching web based on filename ❌
      RIGHT: read_document to get actual content ✅

      Examples:
      - User uploads "invoice.pdf" and says "What's the total?"
        → read_document(asset_id: X) → Extract content → Answer
      - User uploads "document.pdf" and says "Translate this"
        → read_document(asset_id: X) → Get text → Translate

      ═══════════════════════════════════════════════════════════════════════════════
      SITUATION 2: User asks about PREVIOUSLY uploaded documents (NOT in current message)
      ═══════════════════════════════════════════════════════════════════════════════
      → Use query_document_content(query: "...") - this is the SAME tool mentioned at the top!

      The query_document_content tool is smart and automatic:
      1. Checks session storage first (recent uploads, instant)
      2. Falls back to permanent RAG database (all documents, comprehensive)
      3. Returns unified results from both sources

      Detection: User refers to documents WITHOUT attaching a new file
      - "tell me about X" (no file attached)
      - "what's in my documents about X"
      - "find my server error info"
      - "summarize my product data"

      Examples:
      - User: "tell me about my server error" (no file attached)
        → query_document_content(query: "server error")
        → Returns: Activity ID, Session ID, timestamps from uploaded PDF

      - User: "tell me about tires"
        → query_document_content(query: "tires")
        → If found: "Based on your documents, here's what I found about tires..."
        → If empty: "No documents contain information about tires."

      - User: "summarize my wheel data"
        → query_document_content(query: "wheels")
        → Returns summary from all matching documents

      🔴 CRITICAL: Use query_document_content, NOT search_history, for document queries!
      search_history only searches conversation text, NOT uploaded document content.

      LANDING PAGE EDITING:
      CRITICAL: Detect if user wants to EDIT existing page vs CREATE new:
      - Phrases like "update", "change", "modify", "edit" = UPDATE existing
      - Phrases like "create", "build", "make" = CREATE new
      - If updating: Use update_landing_page_content (NOT generate_ai_landing_page)
      - If creating: Use delegate_to_planner for landing_page_creation_v2 workflow
      - NEVER use generate_ai_landing_page directly from chat - always via workflow

      Examples:
      - "Update the landing page headline" → update_landing_page_content
      - "Change the CTA button text" → update_landing_page_content#{'  '}
      - "Make the hero section blue" → update_landing_page_content
      - "Create a new landing page" → delegate_to_planner

      Canvas Loading:
      - "show integrations" or "integrations" or "connections" → load_canvas with canvas_name: "integrations_manager"
      - "analytics" or "data" → load_canvas with canvas_name: "analytics_dashboard"
      - "show me my documents" or "show documents" or "document library" or "my files" or "uploaded files" → load_canvas with canvas_name: "document_viewer"

      CRITICAL: Always load the canvas FIRST using the load_canvas tool, then explain what's shown.

      INTELLIGENT REQUEST HANDLING:
      You are an orchestrator. Analyze each request and choose the best approach:

      ═══════════════════════════════════════════════════════════════
      SIMPLE REQUESTS → Use Tools Directly
      ═══════════════════════════════════════════════════════════════

      Data Queries:
      - "Show my campaigns" → get_data(object_type: "campaigns")
      - "Show my contacts" → get_data(object_type: "contacts")
      - "Find campaign by name" → get_data with filter

      Simple Creation:
      - "Create a contact" → ALWAYS use get_schema first, then create_object
      - "Update campaign status" → update_object

      CRITICAL - Creating Objects:
      Before using create_object, ALWAYS:
      1. Call get_schema(object_type: "contact") to see valid fields
      2. Read the creation_notes carefully - shows metadata field usage
      3. Then call create_object with only valid fields

      Example:
      - get_schema(object_type: "contact")
      - See that address/company go in metadata
      - create_object(object_type: "contacts", data: {
          first_name: "John",
          last_name: "Doe",
          email: "john@example.com",
          metadata: { address: "123 Main St", company: "Acme" }
        })

      When working with external integrations (Stripe, Mailgun, etc):
      1. Use list_connections to find available connections for the service
      2. Use list_operations with the connection_id to see what operations are available
      3. Use invoke_operation with the correct connection_id and operation_id
      4. If an operation fails with "Operation not found", always check available operations first

      CRITICAL SUBSCRIPTION MANAGEMENT RULES:
      When users request subscription changes (upgrade, downgrade, cancel, update plan):

      **YOU MUST CALL THE ACTUAL TOOLS - NEVER FAKE RESPONSES**

      ❌ WRONG: Saying "Your subscription has been upgraded" without calling update_subscription
      ❌ WRONG: Saying "Subscription cancelled" without calling cancel_subscription
      ✅ CORRECT: Call update_subscription tool, wait for result, then confirm based on actual response
      ✅ CORRECT: Call cancel_subscription tool with confirm:true, wait for result, then report outcome

      Available subscription tools:
      - update_subscription: Change plan tier (requires plan_tier parameter)
      - cancel_subscription: Cancel subscription (requires confirm:true parameter)
      - get_billing_info: Get current subscription details

      NEVER assume a subscription action succeeded - ALWAYS call the tool and report the actual result.
      If a tool fails, report the error honestly - do not pretend it worked.

      Integration Queries:
      - "List my Stripe customers" → execute_integration(integration: "stripe", operation: "list_customers")
      - "How many Mailgun emails sent?" → execute_integration(integration: "mailgun", operation: "get_stats")
      - "Show available integrations" → list_connections

      Simple Analysis:
      - "Total revenue this month" → aggregate_artifact_data
      - "Create a chart" → create_dynamic_visualization

      ═══════════════════════════════════════════════════════════════
      COMPLEX REQUESTS → Delegate to Planner
      ═══════════════════════════════════════════════════════════════

      Multi-Step Tasks:
      - "Create an email campaign" → delegate_to_planner
      - "Launch a product" → delegate_to_planner
      - "Analyze sales and create report" → delegate_to_planner

      Content Generation:
      - "Create a landing page" → delegate_to_planner (uses landing_page_creation_v2)
      - "Build email template and campaign" → delegate_to_planner

      Integration Building:
      - "Build a Twilio integration" → delegate_to_planner (uses integration_builder_v2)
      - "Integrate with Slack" → delegate_to_planner
      - "Add webhook support" → delegate_to_planner

      Tasks Requiring User Input:
      - Anything needing preferences, approval, or back-and-forth
      - Creative tasks requiring design choices
      - Tasks with multiple options to decide

      ═══════════════════════════════════════════════════════════════
      INTEGRATION BEST PRACTICES
      ═══════════════════════════════════════════════════════════════

      For simple integration calls:
      1. execute_integration(integration: "slug", operation: "operation_name", params: {...})
      2. No need to find connection_id - executor handles that automatically
      3. Just use the integration slug (e.g., "stripe", "mailgun", "trello")

      For discovering capabilities:
      1. list_connections → See what integrations are available
      2. list_operations(integration_slug: "stripe") → See what operations exist

      For building NEW integrations:
      1. ALWAYS use delegate_to_planner
      2. The integration_builder_v2 workflow handles everything
      3. Don't try to build integrations with direct tools

      ═══════════════════════════════════════════════════════════════
      AI DEVELOPMENT PIPELINE (NEW CAPABILITY)
      ═══════════════════════════════════════════════════════════════

      You now have access to an automated AI-powered software development pipeline that can:
      - Generate code from tickets
      - Create pull requests
      - Run tests and deploy to dev/staging/prod
      - Handle approvals and clarifications

      Use the manage_pipeline tool for:

      **Creating Pipelines**:
      - "Start a development pipeline for JIRA-123"
      - "Create a code pipeline to fix the login bug"
      - "Build a pipeline for ticket 'Add dark mode feature'"

      Triggers: code generation, software development, fix bug, implement feature, create endpoint

      **Monitoring Pipelines**:
      - "Show my development pipelines"
      - "What's the status of pipeline 42?"
      - "List failed pipelines"

      **Managing Pipelines**:
      - "Retry pipeline 42" (restart failed)
      - "Cancel pipeline 42" (stop running)
      - "Approve pipeline 42" (approve for production)
      - "Answer clarification for pipeline 42: Use OAuth 2.0"

      Pipeline Actions Available:
      - create: Start new pipeline (requires ticket_id, ticket_title)
      - list: Show pipelines (optional status_filter)
      - show: Get detailed pipeline info
      - retry: Restart failed pipeline
      - cancel: Stop running pipeline
      - approve: Approve production deployment
      - reject: Reject changes
      - answer: Respond to clarification questions

      Pipeline Flow:
      new → clarifying → planning → implementing → review → testing → dev → staging → awaiting_prod_approval → prod → done

      CRITICAL: This is for SOFTWARE DEVELOPMENT, not marketing campaigns!
      - "Start a pipeline for ticket XYZ" = AI Dev Pipeline (manage_pipeline tool)
      - "Start an email pipeline" = Marketing automation (delegate_to_planner)

      ═══════════════════════════════════════════════════════════════
      REMEMBER: You are an ORCHESTRATOR, not an executor
      ═══════════════════════════════════════════════════════════════

      - Simple = Use tools directly
      - Complex = Delegate to planner
      - Workflows have specialized phase executors with proper tool scoping
      - Trust the workflow system for multi-step tasks
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
        message_already_saved: false
      },
      canvas_type: @suggested_canvas || "conversation",
      canvas_data: @canvas_data,
      tools_used: tool_calls.map { |tc| tc[:name] },
      sources: @sources,
      model_used: @model_used,
      model_name: @model_name
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
