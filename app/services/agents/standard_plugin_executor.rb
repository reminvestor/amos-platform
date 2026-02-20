# StandardPluginExecutor - Default executor for database-backed agent plugins
#
# This executor provides standard AI agent functionality for plugins that don't
# need custom Ruby code. It uses the agent's system prompt, configuration, and
# tools to execute requests via AWS Bedrock.
#
# Usage:
#   agent = Agents::StandardPluginExecutor.new(
#     role: :executor,
#     capabilities: ['email_generation'],
#     system_prompt: "You are a sales email specialist...",
#     config: { max_length: 150, tone: 'professional' },
#     context: { entity: current_entity, user: current_user }
#   )
#   result = agent.run("Generate a sales email for John Smith")
#
class Agents::StandardPluginExecutor
  attr_reader :role, :capabilities, :system_prompt, :config, :context, :execution

  def initialize(role:, capabilities:, system_prompt:, config: {}, context: {})
    @role = role.to_sym
    @capabilities = Array(capabilities)
    @system_prompt = normalize_system_prompt(system_prompt)
    @config = config.with_indifferent_access
    @context = context.with_indifferent_access
    @execution = context[:execution]
  end

  # Main execution method - runs the agent with a prompt
  def run(prompt, additional_context = {})
    merged_context = context.merge(additional_context)
    
    # Check execution strategy
    strategy = context[:agent_plugin]&.execution_strategy || 'standard'
    
    Rails.logger.info "StandardPluginExecutor running with strategy: #{strategy}, prompt: #{prompt.truncate(100)}"

    result = case strategy
    when 'remote_http'
      execute_remote_http(prompt, merged_context)
    when 'workflow'
      execute_workflow(prompt, merged_context)
    else
      # Standard execution via Bedrock
      execute_with_bedrock(prompt, merged_context)
    end

    # Track token usage if we have an execution record
    if execution && result[:usage]
      execution.add_tokens(result[:usage][:total_tokens])
    end

    # If result indicates suspension or error, return the full hash so the caller can handle it
    if result[:status] == 'suspended' || result[:error]
      result
    else
      result[:content]
    end
  end

  # Execute a specific capability
  def execute_capability(capability_name, inputs = {})
    unless capabilities.include?(capability_name)
      raise ArgumentError, "Agent does not have capability: #{capability_name}"
    end

    capability_prompt = <<~PROMPT
      Execute capability: #{capability_name}

      Inputs:
      #{JSON.pretty_generate(inputs)}

      Provide the output according to the capability's contract.
    PROMPT

    run(capability_prompt, inputs)
  end

  private

  def execute_remote_http(prompt, context_data)
    plugin = context[:agent_plugin]
    return { content: "Error: No agent plugin context", error: true } unless plugin
    
    config = plugin.remote_config || {}
    endpoint = config['url'] || config[:url]
    auth_token = config['auth_token'] || config[:auth_token]
    
    raise "Remote agent endpoint not configured" if endpoint.blank?
    
    require 'net/http'
    require 'uri'
    
    uri = URI(endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{auth_token}" if auth_token.present?
    
    payload = {
      prompt: prompt,
      context: context_data.except(:agent_plugin, :execution), # Avoid circular refs/heavy objects
      config: config
    }
    
    request.body = payload.to_json
    
    response = http.request(request)
    
    if response.code.to_i >= 400
      raise "Remote agent failed: #{response.code} - #{response.body}"
    end
    
    body = JSON.parse(response.body)
    
    {
      content: body['content'] || body['response'] || body.to_s,
      usage: body['usage']
    }
  rescue => e
    Rails.logger.error "Remote execution failed: #{e.message}"
    {
      content: "Error executing remote agent: #{e.message}",
      error: true,
      error_message: e.message
    }
  end

  def execute_workflow(prompt, context_data)
    # Placeholder for workflow execution logic
    # This would typically invoke the WorkflowEngine
    {
      content: "Workflow execution not yet implemented in this executor. Please use WorkflowEngine directly.",
      error: true
    }
  end

  def normalize_system_prompt(prompt)
    # Handle both string and hash formats
    case prompt
    when String
      prompt
    when Hash
      prompt['prompt'] || prompt[:prompt] || prompt.to_s
    else
      prompt.to_s
    end
  end

  def build_system_prompt
    parts = []

    # Add current date/time first - critical for date-relative queries
    current_time = Time.current.in_time_zone('America/Los_Angeles')
    parts << "📅 CURRENT DATE/TIME: #{current_time.strftime("%A, %B %d, %Y at %I:%M %p %Z")}"
    parts << "Use this for any date-relative queries like 'today', 'yesterday', 'this week', etc.\n"

    # CRITICAL: Tool usage rules - NEVER hallucinate
    parts << <<~TOOL_RULES
    🚨 CRITICAL TOOL USAGE RULES - FOLLOW EXACTLY:
    
    1. IF YOU NEED A TOOL AND HAVE IT → CALL IT via the tool API
       ✅ Right: Use the tool_use API to call tools
       ❌ WRONG: Print tool calls as text like {"tool": "...", ...}
       
    2. IF YOU NEED DATA/CAPABILITY YOU DON'T HAVE → ASK FOR HELP
       ✅ Right: Use ask_agent_for_help to get another agent
       ❌ WRONG: Make up an answer or hallucinate data
       
    3. WHEN IN DOUBT → DELEGATE
       Better to ask for help than give a wrong answer!
    
    TOOL_RULES

    # Add base system prompt
    parts << normalize_system_prompt(system_prompt) if system_prompt.present?

    # Add configuration context
    if config.present? && config.any?
      parts << "\nConfiguration:"
      parts << JSON.pretty_generate(config)
    end

    # Add business/entity context if configured
    if context[:agent_plugin]&.include_business_data? && context[:entity]
      parts << "\nBusiness Context:"
      parts << "Company Name: #{context[:entity].name}"
      parts << "Industry: #{context[:entity].industry}" if context[:entity].respond_to?(:industry)
      parts << "Description: #{context[:entity].description}" if context[:entity].respond_to?(:description)
      # Add more entity fields as available/needed
    end

    # Add canvas context - what the user is currently viewing
    canvas_context = context[:canvas_context] || config[:canvas_context]
    if canvas_context.present?
      parts << "\n## 🎨 CURRENT USER CANVAS CONTEXT"
      parts << "The user is currently viewing the following in their canvas:"
      parts << "- Canvas Type: #{canvas_context['type'] || canvas_context[:type]}"
      
      canvas_data = canvas_context['data'] || canvas_context[:data] || {}
      if canvas_data['landing_page_id'] || canvas_data[:landing_page_id]
        lp_id = canvas_data['landing_page_id'] || canvas_data[:landing_page_id]
        parts << "- Landing Page ID: #{lp_id}"
        parts << "- ⚡ You can use landing page tools directly with this ID - NO NEED TO ASK the user for the ID!"
      end
      if canvas_data['app_id'] || canvas_data[:app_id]
        app_id = canvas_data['app_id'] || canvas_data[:app_id]
        parts << "- App ID: #{app_id}"
        parts << "- ⚡ You can use app tools directly with this ID - NO NEED TO ASK the user for the ID!"
      end
      if canvas_context['title'] || canvas_context[:title]
        parts << "- Title: #{canvas_context['title'] || canvas_context[:title]}"
      end
      parts << ""
      
      Rails.logger.info "🎨 [Agent] Included canvas context in system prompt: #{canvas_context}"
    end

    # Add memory context (user memories, business insights, agent knowledge)
    memory_context = build_memory_context
    if memory_context.present?
      parts << "\n" + memory_context
    end

    # Add capabilities
    if capabilities.present?
      parts << "\nYour capabilities and required inputs:"
      
      # Load capability definitions to get schemas
      if context[:agent_plugin]
        context[:agent_plugin].agent_capabilities.each do |cap|
          parts << "- #{cap.capability_name}"
          if cap.contract_schema.present? && cap.contract_schema['inputs'].present?
            required = cap.contract_schema['inputs'].select { |i| i['required'] }.map { |i| i['name'] }
            parts << "  - Required Inputs: #{required.join(', ')}" if required.any?
          end
        end
      else
        capabilities.each { |cap| parts << "- #{cap}" }
      end
      
      parts << "\nIMPORTANT: Do NOT guess or hallucinate values for Required Inputs. If they are missing from the context, ask the user for them using the 'ask_user' tool."
    end

    # TASK-FOCUSED AGENT BEHAVIOR
    parts << "\n## 🎯 YOU ARE A TASK-FOCUSED SPECIALIST"
    parts << "You are a specialized worker, NOT a general chatbot. Every conversation with you is about a SPECIFIC TASK."
    parts << ""
    parts << "**Your role:**"
    parts << "- You are a specialist - users come to you for your specific expertise"
    parts << "- Every conversation is a TASK: planning it, executing it, or reviewing the results"
    parts << "- You are NOT Amos (the general assistant) - you don't do casual chat or general questions"
    parts << ""
    parts << "**Task lifecycle:**"
    parts << "1. **PLANNING**: User describes what they want → You confirm understanding and ask clarifying questions"
    parts << "2. **EXECUTING**: You work on the task → Report progress or ask for input if needed"
    parts << "3. **REVIEWING**: You show results → User accepts, requests changes, or provides feedback"
    parts << "4. **ITERATING**: Based on feedback → Make adjustments and show updated results"
    parts << ""
    parts << "**When you receive a greeting or unclear message:**"
    parts << "- If the user says 'hello', 'hi', or something vague, DON'T just greet back casually"
    parts << "- Instead, introduce yourself briefly and ask what task they'd like help with"
    parts << "- Be specific about what you can help with based on your capabilities"
    parts << "- Example: 'Hi! I'm the Landing Page Manager. I can create, edit, or analyze landing pages for you. What would you like to work on?'"
    parts << ""
    parts << "**How to communicate:**"
    # Override conciseness for scheduled tasks with comprehensive output
    if context[:comprehensive_output]
      parts << "- Be professional and thorough - this is a scheduled report task"
      parts << "- Generate comprehensive, detailed output as requested by the user"
    else
      parts << "- Be professional and concise - respect the user's time"
    end
    parts << "- Ask clarifying questions when requirements are unclear - use `ask_user` tool"
    parts << "- Confirm your understanding before starting complex work"
    parts << "- When complete, summarize what you did and ask if it meets their needs"
    parts << "- If the user is unhappy, offer to fix it immediately"
    parts << ""
    parts << "**Task iteration:**"
    parts << "- If a user says 'that's not quite right', 'can you fix this', or 'try again', improve your previous work"
    parts << "- Acknowledge what wasn't right and explain what you're changing"
    parts << "- Follow-up messages in the same conversation are about the SAME task context"
    parts << "- Take feedback gracefully and apply it immediately"
    parts << ""
    parts << "**Working with other agents:**"
    parts << "- You are part of a team of specialized agents, each with different expertise"
    parts << "- If a task requires expertise you don't have, use `ask_agent_for_help` to collaborate"
    parts << "- Don't try to do everything yourself - leverage the team's expertise"
    parts << "- Use `list_available_agents` to see what specialists are available"
    parts << ""
    parts << "**Building your knowledge:**"
    parts << "- You have a personal knowledge base that persists across conversations"
    parts << "- Use `save_to_knowledge_base` to save useful information you discover"
    parts << "- Use `research_and_learn` to search the web and optionally save findings"
    parts << ""
    parts << "**📦 SCRATCHPAD - Sharing data with other agents:**"
    parts << "- The SESSION SCRATCHPAD is shared temporary memory for this conversation"
    parts << "- Use `save_to_scratchpad` to save structured data for other agents or later steps"
    parts << "- Use `read_from_scratchpad` to retrieve data saved by you or other agents"
    parts << "- Use `list_scratchpad` to see what data is available in this session"
    parts << ""
    parts << "IMPORTANT: When you have data that another agent will need:"
    parts << "1. ALWAYS save it to scratchpad with a clear key and description"
    parts << "2. Tell the receiving agent what key to read from"
    parts << "3. Example: After researching VCs, save_to_scratchpad(key: 'vc_research', data: [...], description: '100 AI VCs')"
    parts << ""
    
    # UNIVERSAL CAPABILITY GAP DETECTION
    # Critical for seamless agent collaboration
    parts << "\n## 🤝 CRITICAL: KNOW YOUR LIMITS & COLLABORATE 🤝"
    parts << ""
    parts << "Before starting any task, ask yourself:"
    parts << "1. **What DATA does this task require?** (web research, system data, integrations, documents)"
    parts << "2. **What ACTIONS are needed?** (export, email, create page, visualize)"
    parts << "3. **Do I have tools for ALL of these?** Look at your available tools."
    parts << "4. **If not, WHO can help?** Use `ask_agent_for_help` to delegate."
    parts << ""
    parts << "**🔍 DATA ACCESS - Where does the data come from?**"
    parts << ""
    parts << "If you need data you DON'T have access to, DELEGATE:"
    parts << "- Internet/web research (VCs, competitors, market info, companies) → `web_research_specialist`"
    parts << "- System data (contacts, campaigns, landing pages) → use `get_data` tool"
    parts << "- Integration data (Stripe, QuickBooks) → use `execute_integration` tool"
    parts << "- Uploaded documents → use `read_document` or `query_document_content`"
    parts << ""
    parts << "**🛠️ COMMON COLLABORATION PATTERNS:**"
    parts << ""
    parts << "| Need this... | Delegate to... |"
    parts << "|--------------|----------------|"
    parts << "| Web research, find companies/people | `web_research_specialist` |"
    parts << "| Export data to CSV/Excel/PDF | `document_export_agent` |"
    parts << "| Create landing pages | `landing_page_manager` |"
    parts << "| Generate images | `image_generator` or use `generate_image` |"
    parts << "| Not sure | Use `list_available_agents` first |"
    parts << ""
    parts << "**📋 EXAMPLE WORKFLOW: 'Create a CSV of top 100 VCs'**"
    parts << ""
    parts << "1. You DON'T have web_search → can't research VCs yourself"
    parts << "2. Delegate: `ask_agent_for_help(request_type: 'subtask', helper_agent_slug: 'web_research_specialist', description: 'Research top 100 VCs and save to scratchpad key: vc_research')`"
    parts << "3. Helper agent researches VCs AND saves to scratchpad: `save_to_scratchpad(key: 'vc_research', data: [...])`"
    parts << "4. Read the data: `read_from_scratchpad(key: 'vc_research')`"
    parts << "5. Export: `generate_csv(title: 'Top 100 VCs', data: <data from scratchpad>)`"
    parts << "6. Return the result to the user"
    parts << ""
    parts << "**❌ NEVER:**"
    parts << "- Fabricate data you don't have (no making up company names, emails, etc.)"
    parts << "- Fail silently - if you can't do something, ASK FOR HELP"
    parts << "- Skip steps because you lack a tool - DELEGATE instead"
    parts << ""
    parts << "**✅ ALWAYS:**"
    parts << "- Decompose complex tasks into: gather data → process → output"
    parts << "- Delegate the parts you can't do"
    parts << "- Combine results from multiple agents"
    parts << ""
    
    # UNIVERSAL USER INTERACTION REQUIREMENT
    # This applies to ALL agents, regardless of capabilities defined
    parts << "\n## 🚨 CRITICAL: ASKING USER QUESTIONS 🚨"
    parts << "If you need information from the user (location, preferences, parameters, etc.) you MUST use the `ask_user` tool."
    parts << ""
    parts << "⚠️ WRONG: Responding with text like 'What city would you like weather for?'"
    parts << "   → This COMPLETES your task immediately! The user sees your question but CANNOT reply because the task is done."
    parts << ""
    parts << "✅ RIGHT: Calling ask_user(question: 'What city would you like the weather for?')"
    parts << "   → This PAUSES your task and waits for the user's response. Once they reply, you resume with their answer."
    parts << ""
    parts << "ALWAYS use ask_user tool when you need user input. Never ask questions in plain text responses."
    parts << ""
    parts << "### 🖼️ SHOWING PREVIEWS WITH QUESTIONS"
    parts << "When asking about designs, schemas, or data, use `canvas_content` to show a visual preview:"
    parts << ""
    parts << "```"
    parts << "ask_user("
    parts << "  question: 'Does this schema look right for your Knowledge Base?',"
    parts << "  canvas_title: 'Knowledge Base Schema',"
    parts << "  canvas_content: {"
    parts << "    type: 'design_preview',"
    parts << "    module_name: 'Knowledge Base',"
    parts << "    description: 'Articles and documentation system',"
    parts << "    fields: ["
    parts << "      { name: 'title', type: 'string', description: 'Article title' },"
    parts << "      { name: 'content', type: 'text', description: 'Rich content' },"
    parts << "      { name: 'category', type: 'select', description: 'Category' }"
    parts << "    ]"
    parts << "  }"
    parts << ")"
    parts << "```"
    parts << ""
    parts << "Supported canvas types:"
    parts << "- `design_preview`: Show fields/schema with name, type, description"
    parts << "- `module_preview`: Show module structure with features, canvases, tools arrays"
    parts << "- `data_table`: Show tabular data with headers and rows arrays"
    parts << ""

    # UNIVERSAL ERROR HANDLING AND RETRY LOGIC
    # This applies to ALL agents - learn from errors, don't blindly retry
    parts << "\n## ⚠️ ERROR HANDLING: LEARN AND ADAPT ⚠️"
    parts << ""
    parts << "When a tool call fails, you MUST:"
    parts << "1. **READ the error message carefully** - it tells you exactly what went wrong"
    parts << "2. **ADJUST your approach** - fix the specific issue mentioned"
    parts << "3. **DO NOT retry the same call** - repeating a failed call wastes time and tokens"
    parts << ""
    parts << "Common patterns:"
    parts << "- 'X is required' → You forgot a required parameter. Add it."
    parts << "- 'not found' → The resource doesn't exist. Check spelling or create it first."
    parts << "- 'validation failed' → Your data format is wrong. Check the schema."
    parts << ""
    parts << "If an error includes an `example_call`, use it as a template for your retry."
    parts << ""

    # UNIVERSAL CONTEXT MAPPING INSTRUCTION
    # Agents receive context values but must pass them explicitly to tools
    parts << "\n## ⚙️ USING CONTEXT VALUES IN TOOL CALLS ⚙️"
    parts << ""
    parts << "Your Configuration may contain hints like `module_slug`, `canvas_type`, etc."
    parts << "These are for YOUR information - tools DON'T read your Configuration automatically!"
    parts << ""
    parts << "You MUST pass context values as explicit tool parameters."
    parts << "Example: If Configuration has `canvas_type: 'dashboard'`, you still must call:"
    parts << "  update_module(canvas_definition: { canvas_type: 'dashboard', name: '...' })"
    parts << ""

    # Check if this is a scheduled task requiring comprehensive output
    # This overrides the normal "be concise" behavior for research/report tasks
    if context[:comprehensive_output] || context[:scheduled_task]
      if context[:comprehensive_output]
        Rails.logger.info "📋 [Agent] COMPREHENSIVE OUTPUT MODE - overriding conciseness for scheduled task"
        parts << "\n## 🚨 SCHEDULED TASK - COMPREHENSIVE OUTPUT REQUIRED 🚨"
        parts << ""
        parts << "⚠️ THIS IS A SCHEDULED REPORT TASK - OVERRIDE YOUR NORMAL CONCISENESS!"
        parts << ""
        parts << "**FOR THIS TASK YOU MUST:**"
        parts << "- Generate DETAILED, COMPREHENSIVE output (NOT concise summaries)"
        parts << "- Include ALL sections requested in the user's prompt"
        parts << "- Provide thorough analysis and explanations"
        parts << "- Include source links and references"
        parts << "- Follow the EXACT format specified in the prompt"
        parts << "- Use multiple searches to gather comprehensive information"
        parts << ""
        parts << "**DO NOT:**"
        parts << "- Give brief summaries when detailed content was requested"
        parts << "- Skip sections the user asked for"
        parts << "- Say 'I'll keep this brief' or similar"
        parts << "- Truncate or abbreviate the output"
        parts << ""
        parts << "The user scheduled this task to receive FULL, DETAILED reports - deliver exactly that."
        parts << ""
      end
    end

    # Output Format - context dependent
    parts << "\n## OUTPUT FORMAT:"
    parts << ""
    
    # Modify output format instructions based on comprehensive_output flag
    if context[:comprehensive_output]
      parts << "**For this scheduled report task:**"
      parts << "- Generate the complete, detailed report as requested"
      parts << "- Use markdown format with proper headers and sections"
      parts << "- Include all source links and references"
      parts << "- Do NOT use JSON format - output the full report directly"
      parts << ""
    else
      parts << "**For conversational responses** (greetings, questions, status updates, clarifications):"
      parts << "- Respond in natural, conversational text"
      parts << "- Be concise and professional"
      parts << "- Do NOT use JSON format for simple conversation"
      parts << ""
      parts << "**For completed tasks with deliverables** (reports, code, data, documents):"
      parts << "- Use JSON format with this schema:"
      parts << "{"
      parts << "  \"summary\": \"Concise message explaining what you created (2-3 sentences).\","
      parts << "  \"content\": \"The detailed output - report, code, data, etc.\","
      parts << "  \"format\": \"markdown\" | \"html\" | \"json\" | \"code\" | \"text\""
      parts << "}"
      parts << "- Do NOT wrap JSON in markdown code blocks"
      parts << ""
      parts << "**When to use each:**"
      parts << "- User says 'hello' → Conversational response (introduce yourself, ask about task)"
      parts << "- User asks a question → Conversational response (answer or ask clarifying questions)"
      parts << "- User requests something complex → Use ask_user to clarify, then produce JSON deliverable"
      parts << "- You create a document/report/code → JSON with summary and content"
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # FINAL, CRITICAL ANTI-HALLUCINATION RULE (placed at END for maximum attention)
    # ═══════════════════════════════════════════════════════════════════════════
    parts << ""
    parts << "## ⛔ MANDATORY TOOL USAGE - NEVER NARRATE ACTIONS ⛔"
    parts << ""
    parts << "This is the MOST IMPORTANT rule you must follow:"
    parts << ""
    parts << "**IF THE USER ASKS YOU TO CHANGE, EDIT, CREATE, UPDATE, FIX, OR MODIFY ANYTHING:**"
    parts << "→ You MUST call a tool to do it"
    parts << "→ You MUST NOT respond with text claiming you did it"
    parts << "→ Your response without a tool call is a LIE"
    parts << ""
    parts << "**EXAMPLES OF WHAT YOU MUST NEVER DO:**"
    parts << "❌ 'I've repositioned your video!' (without tool call = LIE)"
    parts << "❌ 'Done! I updated the headline.' (without tool call = LIE)"
    parts << "❌ 'I've made the changes you requested.' (without tool call = LIE)"
    parts << "❌ 'The edit is complete!' (without tool call = LIE)"
    parts << ""
    parts << "**WHAT YOU MUST DO INSTEAD:**"
    parts << "✅ Call the appropriate tool (e.g., edit_landing_page_section, update_landing_page_content)"
    parts << "✅ Wait for the tool result"
    parts << "✅ Report the ACTUAL tool result to the user"
    parts << ""
    parts << "**If you see previous messages where you claimed to make changes but there's no tool call between the user request and your claim, those were ERRORS. Do not repeat them. Actually call the tool this time.**"
    parts << ""

    parts.join("\n")
  end

  def execute_with_bedrock(prompt, context_data)
    # Store prompt for tool discovery
    @current_prompt = prompt
    
    # Determine which model to use
    model_name = get_model_name

    # Pass full context to BedrockService so tools can access it
    # This includes agent_plugin, task_session, session_id, etc.
    bedrock_service = BedrockService.new(
      entity: context[:entity],
      user: context[:user],
      custom_model_id: model_name,
      context: context,  # Pass full context for tool execution
      execution: execution  # Pass execution record for token tracking
    )

    # Get available tools for this agent
    # NOTE: 'ask_user' is added by get_available_tools if available
    # This now includes RAG-discovered tools based on the prompt
    tools = get_available_tools

    # Build enhanced system prompt with configuration and capabilities
    system_prompt_text = build_system_prompt

    # Initialize messages (conversation history)
    # If we are resuming, load the context; otherwise start fresh
    messages = if execution && execution.conversation_context.present?
                 execution.conversation_context.map(&:deep_symbolize_keys)
               else
                 [{ role: 'user', content: prompt }]
               end

    # CRITICAL: Sanitize conversation history to detect and annotate hallucinated responses
    # If an assistant message claims to have made changes, but there's no tool_use in that
    # message, and the next user message indicates failure, annotate the hallucination.
    messages = sanitize_hallucinated_history(messages)

    # If resuming from a tool call (e.g., ask_user answer), append the result
    if execution && execution.status == 'running' && execution.conversation_context.present?
      # Check if we have a pending input request that was just answered
      input_request = execution.agent_plugin.agent_input_requests.where(agent_plugin_execution_id: execution.id).answered.order(responded_at: :desc).first
      
      if input_request
        # Create the tool result for ask_user
        tool_use_id = find_last_tool_use_id(messages, 'ask_user')
        
        if tool_use_id
          ask_user_result = {
            tool_result: {
              tool_use_id: tool_use_id,
              content: [
                { text: input_request.response_content }
              ],
              status: "success"
            }
          }
          
          # Check if the last message is already a user message with tool_results
          # If so, we need to merge the ask_user result into it (Claude requires all tool
          # results for one assistant turn to be in the same user message)
          last_message = messages.last
          if last_message && last_message[:role] == 'user' && last_message[:content].is_a?(Array)
            # Check if it contains tool_results (meaning it's a partial result from before suspension)
            has_tool_results = last_message[:content].any? { |c| c[:tool_result] || c['tool_result'] }
            if has_tool_results
              # Merge ask_user result into the existing user message
              last_message[:content] << ask_user_result
              Rails.logger.info "📝 Merged ask_user result into existing tool_results message"
            else
              # Last user message is not tool_results, append a new message
              messages << { role: 'user', content: [ask_user_result] }
            end
          else
            # No user message at the end, append a new one
            messages << { role: 'user', content: [ask_user_result] }
          end
          
          Rails.logger.info "📝 Resuming execution with user answer: #{input_request.response_content.truncate(50)}"
        end
      end
    end

    execution_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    begin
      # Call BedrockService with the correct method
      # This handles the turn loop internally for simple tools,
      # but we need to catch the suspension for ask_user
      content = bedrock_service.send_message_converse(
        system_prompt_text,
        messages,
        model: model_name,
        max_tokens: config[:max_tokens] || 8192,
        temperature: config[:temperature] || 0.7,
        tools: tools
      )

      # Record successful execution to Agent Lightning
      record_agent_execution_to_lightning(
        agent_role: context[:agent_plugin]&.slug || role.to_s,
        prompt: prompt,
        response: content,
        duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - execution_start_time) * 1000).round,
        status: 'success',
        tools_used: tools.map { |t| t[:name] }
      )

      # Sanitize output to ensure valid JSON
      # Strip markdown code blocks if present
      if content.is_a?(String)
        # Remove markdown code blocks
        cleaned_content = content.gsub(/^```json\s*/, '').gsub(/^```\s*/, '').gsub(/```$/, '').strip
        
        # If content still has preamble text but contains a JSON object, extract it
        # This regex finds the first { and the last }
        if cleaned_content =~ /(\{.*\})/m
          possible_json = $1
          # Verify it parses
          begin
            JSON.parse(possible_json)
            cleaned_content = possible_json
          rescue JSON::ParserError
            # If it doesn't parse (e.g. truncated), still prefer the extracted block over the full text
            # This removes the "Here is your JSON:" preamble
            cleaned_content = possible_json
          end
        end
        
        content = cleaned_content
      end

      # HALLUCINATION DETECTION: Check if agent claims to have made changes
      # but there's no indication that tools were actually called
      tools_actually_called = bedrock_service.tools_called
      no_tools_were_called = tools_actually_called.empty?
      
      Rails.logger.info "🔧 Tools actually called: #{tools_actually_called.inspect}" if tools_actually_called.any?
      
      if no_tools_were_called && detect_action_hallucination(content, prompt)
        @hallucination_retry_count ||= 0
        @hallucination_retry_count += 1
        
        if @hallucination_retry_count < 2
          Rails.logger.warn "🎭 ACTION HALLUCINATION DETECTED: Agent claimed to make changes without calling any tools!"
          Rails.logger.warn "🎭 Response: #{content.to_s.truncate(300)}"
          
          # Build retry messages in the correct Bedrock Converse API format
          # Note: Converse API uses { text: "..." } not { type: "text", text: "..." }
          correction_instruction = "⚠️ CRITICAL ERROR: You said you made changes (e.g., 'I've repositioned', 'I've updated') but you did NOT actually call any tools! " \
            "Your response is meaningless without tool execution. You MUST call the appropriate tool (like edit_landing_page_section, update_landing_page_content, etc.) to ACTUALLY make the changes. " \
            "DO NOT respond with text claiming changes - CALL THE TOOL NOW."
          
          retry_messages = messages + [
            { role: "assistant", content: [{ text: content.to_s }] },
            { role: "user", content: [{ text: correction_instruction }] }
          ]
          
          # Retry with the correction
          retry_content = bedrock_service.send_message_converse(
            system_prompt_text,
            retry_messages,
            model: model_name,
            max_tokens: config[:max_tokens] || 8192,
            temperature: config[:temperature] || 0.7,
            tools: tools
          )
          content = retry_content
          
          # Check again if tools were called after retry
          if bedrock_service.tools_called.any?
            Rails.logger.info "🎭 Retry successful! Tools called: #{bedrock_service.tools_called.inspect}"
          else
            Rails.logger.warn "🎭 Retry failed - agent still didn't call tools"
          end
        end
      end

      # Return in consistent format
      {
        content: content,
        usage: nil # BedrockService handles usage tracking internally
      }
    rescue => e
      # Check for ExecutionSuspended by name if class matching failed
      if e.class.name.include?('ExecutionSuspended') || e.is_a?(Tools::AskUserTool::ExecutionSuspended)
        # Capture the current conversation state before suspending
        if execution
          Rails.logger.info "⏸️ Execution suspended for user input: #{e.message}"
          
          # Save the conversation history so we can resume later
          if e.respond_to?(:conversation_context) && e.conversation_context
            execution.update!(conversation_context: e.conversation_context)
          end
          
          # Return a special "suspended" result
          return {
            content: "Waiting for user input...",
            usage: nil,
            status: 'suspended'
          }
        end
      end

      Rails.logger.error "StandardPluginExecutor failed: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")

      # Record failed execution to Agent Lightning
      record_agent_execution_to_lightning(
        agent_role: context[:agent_plugin]&.slug || role.to_s,
        prompt: prompt,
        response: nil,
        duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - execution_start_time) * 1000).round,
        status: 'failed',
        error_message: e.message
      )

      # Return error in consistent format
      {
        content: "Error executing agent: #{e.message}",
        error: true,
        error_message: e.message
      }
    end
  end

  def get_available_tools
    return [] unless context[:agent_plugin]

    agent_plugin = context[:agent_plugin]
    catalog = Tools::ToolCatalog.instance
    
    # Refresh catalog to pick up any newly created tools
    catalog.refresh_dynamic_tools!

    # Start with COLLABORATION TOOLS that ALL agents get
    # This enables agent-to-agent collaboration (ask_agent_for_help, list_available_agents, ask_user)
    # V3: Core collaboration tools (previously from TieredDiscoveryService)
    collaboration_tool_names = %w[ask_user platform_query platform_create platform_update discover].dup
    
    # Add explicitly assigned tool names from agent configuration
    assigned_tool_names = agent_plugin.agent_tools.pluck(:tool_name)
    
    # Combine: collaboration tools + assigned tools
    all_tool_names = (collaboration_tool_names + assigned_tool_names).uniq
    
    # Load tool definitions
    base_tools = all_tool_names.filter_map { |name| catalog.get_tool_definition(name) }
    
    # RAG Search: Find additional relevant tools based on the task
    # This allows agents to discover and use tools they weren't explicitly assigned
    additional_tools = discover_relevant_tools(all_tool_names)
    
    # Merge: base tools first, then discovered tools
    all_tools = base_tools + additional_tools
    
    collab_count = collaboration_tool_names.size
    assigned_count = assigned_tool_names.size
    discovered_count = additional_tools.size
    
    Rails.logger.info "🤝 Agent #{agent_plugin.name} loaded #{collab_count} collaboration + #{assigned_count} assigned + #{discovered_count} discovered tools (#{all_tools.size} total)"
    
    all_tools
  rescue => e
    Rails.logger.warn "Failed to load tools for agent: #{e.message}"
    []
  end

  def discover_relevant_tools(exclude_names = [])
    return [] unless @current_prompt.present?
    
    # AGENT-COMPOSED TOOL QUERY: Instead of using raw user prompt,
    # have the agent analyze what tools it needs and compose a targeted search
    tool_query = compose_tool_discovery_query(@current_prompt)
    
    Rails.logger.info "🔍 Tool discovery - Original: #{@current_prompt.truncate(80)}"
    Rails.logger.info "🔍 Tool discovery - Agent query: #{tool_query.truncate(100)}"
    
    catalog = Tools::ToolCatalog.instance
    discovered = []
    
    # 1. RAG search ToolDefinitions (custom tools) based on AGENT'S tool query
    if defined?(ToolDefinition) && ToolDefinition.table_exists?
      begin
        # Search for relevant custom tools using agent-composed query
        relevant_custom_tools = ToolDefinition.search_by_similarity(tool_query, limit: 5)
        
        relevant_custom_tools.each do |td|
          next if exclude_names.include?(td.name)
          next if td.security_rating == 'fail' # Skip failed security checks
          
          tool_def = catalog.get_tool_definition(td.name)
          if tool_def
            discovered << tool_def
            Rails.logger.info "🔍 Discovered custom tool via RAG: #{td.name}"
          end
        end
      rescue => e
        Rails.logger.warn "RAG search for custom tools failed: #{e.message}"
      end
    end
    
    # 2. Semantic search on class-based tools using agent's query
    begin
      class_tool_results = ClassToolEmbeddingsService.instance.search(tool_query, limit: 5)
      
      class_tool_results.each do |result|
        next if exclude_names.include?(result[:name])
        next if discovered.any? { |t| t[:name] == result[:name] }
        next if discovered.size >= 10
        next if result[:similarity] < 0.3 # Only include reasonably similar tools
        
        tool_def = catalog.get_tool_definition(result[:name])
        if tool_def
          discovered << tool_def
          Rails.logger.info "🔍 Discovered class tool via semantic search: #{result[:name]} (similarity: #{result[:similarity].round(3)})"
        end
      end
    rescue => e
      Rails.logger.warn "Class tool semantic search failed: #{e.message}"
    end
    
    # 3. Keyword-based discovery from system tools (fallback)
    # Look for tools that match keywords in the task
    task_keywords = extract_task_keywords(@current_prompt)
    
    if task_keywords.any?
      catalog.all_tools.each do |name, info|
        next if exclude_names.include?(name)
        next if discovered.any? { |t| t[:name] == name }
        next if discovered.size >= 10 # Limit total discovered tools
        
        description = info[:metadata][:description]&.downcase || ''
        tool_name = name.downcase
        
        # Check if tool matches any task keywords
        if task_keywords.any? { |kw| description.include?(kw) || tool_name.include?(kw) }
          tool_def = catalog.get_tool_definition(name)
          if tool_def
            discovered << tool_def
            Rails.logger.info "🔍 Discovered system tool via keyword: #{name}"
          end
        end
      end
    end
    
    discovered.take(10) # Limit to 10 additional tools max
  rescue => e
    Rails.logger.warn "Tool discovery failed: #{e.message}"
    []
  end

  # Build memory context using the Agents::MemoryContext service
  # This gives agents access to user memories, business insights, and agent-specific knowledge
  def build_memory_context
    return nil unless context[:agent_plugin] && context[:user] && context[:entity]
    
    begin
      memory_service = Agents::MemoryContext.new(
        agent: context[:agent_plugin],
        user: context[:user],
        entity: context[:entity]
      )
      
      # Build context with the current task/prompt
      memory_data = memory_service.build_context(@current_prompt)
      
      # Format for inclusion in system prompt
      formatted = memory_service.format_for_prompt(memory_data)
      
      return nil if formatted.blank?
      
      formatted
    rescue => e
      Rails.logger.warn "Could not build agent memory context: #{e.message}"
      nil
    end
  end

  # AGENT-COMPOSED TOOL QUERY
  # Instead of using raw user prompt for tool discovery, the agent analyzes
  # the task and composes a focused query describing what tools it needs.
  # This dramatically improves tool discovery accuracy.
  def compose_tool_discovery_query(task_description)
    return task_description if task_description.blank?
    
    # Step 1: Detect task requirements using pattern matching (fast)
    requirements = detect_task_requirements(task_description)
    
    # Step 2: Build a tool-focused search query from requirements
    if requirements.any?
      tool_terms = requirements.map { |r| REQUIREMENT_TO_TOOL_TERMS[r] }.flatten.compact.uniq
      
      # Combine detected terms into a search query
      query = tool_terms.join(' ')
      Rails.logger.info "🧠 Agent detected requirements: #{requirements.join(', ')}"
      
      # Include some of the original task for context
      "#{query} #{task_description.first(100)}"
    else
      # Fallback to original prompt if no patterns matched
      task_description
    end
  rescue => e
    Rails.logger.warn "Tool query composition failed: #{e.message}"
    task_description
  end
  
  # Sanitize conversation history to detect and annotate hallucinated responses
  # If an assistant message claims to have made changes but there's no tool_use in that
  # message, and the next user message indicates failure ("didn't work", "try again", etc.),
  # we annotate the hallucinated response so the model knows not to repeat the pattern.
  # Also detects raw JSON tool call parameters that were output as text instead of tool_use.
  def sanitize_hallucinated_history(messages)
    return messages if messages.nil? || messages.empty?
    
    hallucination_patterns = [
      /i['']ve (repositioned|updated|changed|moved|edited|fixed)/i,
      /✅.*i['']ve/i,
      /made the (edit|change|update)/i,
      /the video is now/i,
      /is now.*(below|above|beside)/i
    ]
    
    failure_patterns = [
      /didn['']?t work/i,
      /that (didn|did not|doesn|does not|failed)/i,
      /try again/i,
      /still (not|didn|hasn)/i,
      /error/i,
      /not.*working/i
    ]
    
    sanitized = []
    messages.each_with_index do |msg, i|
      next_msg = messages[i + 1]
      
      if msg[:role] == 'assistant'
        content_text = extract_text_from_content(msg[:content])
        has_tool_use = content_has_tool_use?(msg[:content])
        claims_action = hallucination_patterns.any? { |p| content_text =~ p }
        
        # CRITICAL: Detect raw JSON tool call parameters output as text
        # This happens when the model outputs {"landing_page_id": 789, "section": "hero"...}
        # instead of properly calling the tool
        is_raw_json_tool_call = is_json_tool_call_output?(content_text)
        
        # Check if next user message indicates failure
        next_indicates_failure = false
        if next_msg && next_msg[:role] == 'user'
          next_text = extract_text_from_content(next_msg[:content])
          next_indicates_failure = failure_patterns.any? { |p| next_text =~ p }
        end
        
        # If it's raw JSON tool call output, always replace it - this is a critical error
        if is_raw_json_tool_call && !has_tool_use
          Rails.logger.warn "🎭 Detected RAW JSON tool call output in conversation history at index #{i} - replacing with warning"
          annotated_content = "[SYSTEM NOTE: The previous response incorrectly output JSON tool parameters as text instead of calling the tool. This is WRONG. You MUST use the tool_use mechanism to call tools - never output JSON parameters as text. The tool was NOT executed.]\n\nI apologize, I made an error and need to properly call the tool now."
          sanitized << { role: msg[:role], content: annotated_content }
        # If claimed action without tool use AND user indicated failure, annotate it
        elsif claims_action && !has_tool_use && next_indicates_failure
          Rails.logger.warn "🎭 Detected hallucinated response in conversation history at index #{i}"
          annotated_content = "[SYSTEM NOTE: The following response was a HALLUCINATION - the assistant claimed to make changes but did NOT call any tools. Do not repeat this pattern.]\n\n#{content_text}"
          sanitized << { role: msg[:role], content: annotated_content }
        else
          sanitized << msg
        end
      else
        sanitized << msg
      end
    end
    
    sanitized
  end
  
  # Detect if content is raw JSON that looks like tool call parameters
  # e.g., {"landing_page_id": 789, "section": "hero", "action": "replace", "content": "..."}
  def is_json_tool_call_output?(content)
    return false if content.blank?
    
    stripped = content.to_s.strip
    
    # Check if it starts with { and ends with }
    return false unless stripped.start_with?('{') && stripped.end_with?('}')
    
    begin
      parsed = JSON.parse(stripped)
      return false unless parsed.is_a?(Hash)
      
      # Check for common tool call parameter patterns
      tool_call_keys = %w[
        landing_page_id section action content instruction
        landing_page_name design_description
        agent_type task_description
        query search_query
        file_path old_string new_string
      ]
      
      # If the JSON has any of these keys, it's likely tool call output
      (parsed.keys.map(&:to_s) & tool_call_keys).any?
    rescue JSON::ParserError
      false
    end
  end
  
  def extract_text_from_content(content)
    return content.to_s if content.is_a?(String)
    return '' unless content.is_a?(Array)
    
    content.filter_map do |item|
      item[:text] || item['text'] if item.is_a?(Hash)
    end.join("\n")
  end
  
  def content_has_tool_use?(content)
    return false unless content.is_a?(Array)
    content.any? { |item| item.is_a?(Hash) && (item[:tool_use] || item['tool_use']) }
  end

  # Detect when an agent claims to have made changes but didn't actually call tools
  # This catches the pattern where models say "I've updated/repositioned/changed..." 
  # without actually executing a tool
  def detect_action_hallucination(response, original_prompt)
    return false if response.blank?
    
    response_text = response.to_s.downcase
    prompt_text = original_prompt.to_s.downcase
    
    # Patterns that indicate the agent claims to have done something
    action_claimed_patterns = [
      /i['']ve (already )?(updated|changed|modified|repositioned|moved|edited|fixed|added|removed|created|addressed|made)/i,
      /i (updated|changed|modified|repositioned|moved|edited|fixed|added|removed|created|made) (the|your|this)/i,
      /✅\s*(i['']ve|done|updated|changed|repositioned|moved|complete)/i,
      /what (i |changed|updated|modified)/i,
      /new (layout|design|structure|positioning)/i,
      /changes? (made|applied|complete)/i,
      /successfully (updated|changed|modified|repositioned)/i,
      /made the (edit|change|update|fix)/i,
      /the video is now/i,
      /i['']ve already/i,
      /this is now/i,
      /is now.*(below|above|beside|next to)/i,
      /now.*(positioned|placed|sitting|located)/i,
      /i applied/i,
      /applied the/i,
      /final layout/i,
      /locked in/i
    ]
    
    # Patterns that suggest the task REQUIRED a tool action
    task_needs_action_patterns = [
      /move|reposition|change|update|edit|fix|modify|put|place|add|remove|delete/i
    ]
    
    # Check if task needed action AND agent claims to have done it
    task_needed_action = task_needs_action_patterns.any? { |p| prompt_text =~ p }
    agent_claimed_action = action_claimed_patterns.any? { |p| response_text =~ p }
    
    # Response claims to have made changes
    is_action_claim = response_text.length < 2500 && agent_claimed_action
    
    # If the agent claimed an action but the response looks like pure text
    # (no JSON structure from tool results, no tool invocation markers)
    no_tool_evidence = !response_text.include?('tool_use_id') && 
                       !response_text.include?('"success"') &&
                       !response_text.include?('"result"') &&
                       !response_text.include?('tool result') &&
                       !response_text.include?('executed')
    
    # Hallucination detected if:
    # 1. Task needed action AND
    # 2. Agent claimed action AND
    # 3. No evidence of actual tool use
    if task_needed_action && agent_claimed_action && no_tool_evidence && is_action_claim
      Rails.logger.warn "🎭 Hallucination check triggered - prompt: '#{prompt_text.truncate(100)}', claimed_action: #{agent_claimed_action}"
      return true
    end
    
    false
  end
  
  # Mapping from detected requirements to tool search terms
  REQUIREMENT_TO_TOOL_TERMS = {
    research: %w[web_search search internet research find information lookup],
    export: %w[generate_csv generate_excel generate_pdf export download spreadsheet document],
    data_access: %w[get_data query fetch retrieve database],
    email: %w[email send message notify campaign],
    visualization: %w[chart graph visualize plot dashboard create_dynamic_visualization],
    integration: %w[integration api connect external execute_integration],
    document_read: %w[read_document query_document_content pdf analyze],
    landing_page: %w[landing_page generate_ai_landing_page website page],
    image: %w[generate_image image picture visual design],
    scheduling: %w[schedule task reminder create_scheduled_task],
    agent_help: %w[ask_agent_for_help delegate collaborate specialist]
  }.freeze
  
  # Detect what the task requires based on patterns
  def detect_task_requirements(text)
    return [] if text.blank?
    
    text_lower = text.downcase
    requirements = []
    
    # Research indicators - needs web_search or research tools
    research_patterns = [
      'research', 'find out', 'look up', 'search for', 'list of', 'compile',
      'investors', 'vcs', 'venture capital', 'competitors', 'companies',
      'market', 'industry', 'prospects', 'leads', 'information about',
      'who are', 'what are the top', 'best', 'find me'
    ]
    requirements << :research if research_patterns.any? { |p| text_lower.include?(p) }
    
    # Export indicators - needs generate_csv, generate_excel, generate_pdf
    export_patterns = [
      'csv', 'excel', 'xlsx', 'pdf', 'export', 'download', 'spreadsheet',
      'create a document', 'generate a report', 'save as', 'file'
    ]
    requirements << :export if export_patterns.any? { |p| text_lower.include?(p) }
    
    # Data access indicators
    data_patterns = ['get data', 'fetch', 'retrieve', 'database', 'from the system', 'my contacts', 'my campaigns']
    requirements << :data_access if data_patterns.any? { |p| text_lower.include?(p) }
    
    # Email indicators
    email_patterns = ['send email', 'email campaign', 'send a message', 'notify', 'outreach']
    requirements << :email if email_patterns.any? { |p| text_lower.include?(p) }
    
    # Visualization indicators
    viz_patterns = ['chart', 'graph', 'visualize', 'plot', 'dashboard', 'metrics', 'analytics']
    requirements << :visualization if viz_patterns.any? { |p| text_lower.include?(p) }
    
    # Integration indicators
    integration_patterns = ['stripe', 'quickbooks', 'integration', 'api', 'connect to', 'sync']
    requirements << :integration if integration_patterns.any? { |p| text_lower.include?(p) }
    
    # Document reading indicators
    doc_patterns = ['read the document', 'from the pdf', 'uploaded file', 'analyze the document']
    requirements << :document_read if doc_patterns.any? { |p| text_lower.include?(p) }
    
    # Landing page indicators
    landing_patterns = ['landing page', 'website', 'create a page', 'web page']
    requirements << :landing_page if landing_patterns.any? { |p| text_lower.include?(p) }
    
    # Image generation indicators
    image_patterns = ['generate image', 'create image', 'picture', 'visual', 'design a']
    requirements << :image if image_patterns.any? { |p| text_lower.include?(p) }
    
    # Scheduling indicators
    schedule_patterns = ['schedule', 'remind me', 'every day', 'weekly', 'recurring']
    requirements << :scheduling if schedule_patterns.any? { |p| text_lower.include?(p) }
    
    requirements
  end

  # AGENT-COMPOSED TOOL QUERY
  # Instead of using raw user prompt for tool discovery, have the agent
  # analyze the task and compose a focused query describing what tools it needs.
  # Uses Haiku for speed - this is a simple analysis task.
  def compose_tool_discovery_query(task_description)
    return task_description if task_description.blank?
    
    begin
      # Use a fast, cheap model for tool analysis
      haiku_service = BedrockService.new(
        entity: context[:entity],
        user: context[:user],
        custom_model_id: 'qwen3-next-80b'  # Qwen is fast and cheap for simple tasks
      )
      
      messages = [{
        role: 'user',
        content: <<~PROMPT
          Analyze this task and list what tool CAPABILITIES are needed to complete it.
          
          Task: #{task_description.truncate(500)}
          
          Output ONLY a comma-separated list of capability keywords like:
          web_search, research, export_csv, export_excel, generate_pdf, data_query, 
          email_send, visualization, chart, api_integration, document_read, 
          landing_page, image_generation, scheduling, agent_collaboration
          
          Example: "Create a CSV of top VCs" → web_search, research, export_csv
          Example: "Send email to my contacts" → data_query, email_send
          Example: "Generate a sales report chart" → data_query, visualization, chart
          
          Just the keywords, nothing else:
        PROMPT
      }]
      
      response = haiku_service.complete(messages: messages, max_tokens: 100, temperature: 0.3)
      
      # Extract text from response
      response_text = if response.is_a?(Hash) && response[:content]
                        response[:content]
                      elsif response.is_a?(String)
                        response
                      else
                        nil
                      end
      
      if response_text.present?
        # Clean up the response and convert to search terms
        capabilities = response_text.strip.downcase.gsub(/[^\w,\s_]/, '').split(',').map(&:strip)
        tool_query = capabilities.join(' ')
        
        Rails.logger.info "🧠 Agent-composed tool query: #{tool_query}"
        tool_query
      else
        task_description
      end
    rescue => e
      Rails.logger.warn "Tool query composition failed (using original): #{e.message}"
      task_description
    end
  end

  def extract_task_keywords(text)
    return [] if text.blank?
    
    # Common task-related keywords that might indicate tool needs
    keyword_patterns = {
      'weather' => ['weather', 'forecast', 'temperature', 'climate'],
      'search' => ['search', 'find', 'look up', 'research', 'google', 'web_search'],
      'calculate' => ['calculate', 'compute', 'roi', 'math', 'percentage'],
      'data' => ['data', 'database', 'query', 'fetch', 'retrieve'],
      'email' => ['email', 'send', 'message', 'notify'],
      'document' => ['document', 'pdf', 'file', 'read', 'analyze'],
      'api' => ['api', 'integration', 'connect', 'external'],
      'chart' => ['chart', 'graph', 'visualize', 'plot', 'dashboard'],
      'metric' => ['metric', 'analytics', 'statistics', 'report'],
      # Research-related patterns - indicate need for web_search
      'web_search' => ['investors', 'vcs', 'venture capital', 'competitors', 'companies', 
                       'market', 'industry', 'prospects', 'leads', 'list of', 'compile', 
                       'research', 'internet', 'online', 'look up', 'information about']
    }
    
    text_lower = text.downcase
    matched_keywords = []
    
    keyword_patterns.each do |category, patterns|
      if patterns.any? { |p| text_lower.include?(p) }
        matched_keywords << category
        matched_keywords.concat(patterns.select { |p| text_lower.include?(p) })
      end
    end
    
    matched_keywords.uniq
  end

  def get_model_name
    return nil unless context[:agent_plugin]

    # For testing: allow config to override agent's default model
    # Otherwise use agent's model preference, or fall back to config, then default
    config[:model] || context[:agent_plugin].ai_model || 'qwen3-next-80b'
  end

  def get_model_config
    return {} unless context[:agent_plugin]

    # Additional model-specific configuration
    context[:agent_plugin].model_config || {}
  end
  
  def find_last_tool_use_id(messages, tool_name)
    messages.reverse_each do |msg|
      next unless msg[:role] == 'assistant'
      
      content = msg[:content]
      if content.is_a?(Array)
        content.each do |block|
          # Handle both snake_case (internal) and camelCase (AWS SDK) keys
          tool_use = block[:tool_use] || block[:toolUse] || block['tool_use'] || block['toolUse']
          
          if tool_use
            # Handle both symbol and string keys
            t_name = tool_use[:name] || tool_use['name']
            t_id = tool_use[:tool_use_id] || tool_use['tool_use_id'] || tool_use[:toolUseId] || tool_use['toolUseId']
            
            return t_id if t_name == tool_name
          end
        end
      end
    end
    nil
  end
end
