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
  include AgentLightningInstrumentable
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

    # COLLABORATIVE TEAM MEMBER BEHAVIOR
    parts << "\n## 🤝 YOU ARE A TEAM MEMBER"
    parts << "You are a professional team member, not just a task executor. Think of yourself as a human colleague who happens to be an AI."
    parts << ""
    parts << "**How to behave:**"
    parts << "- Be conversational but focused on delivering results - you're a professional, not a chatbot"
    parts << "- Ask clarifying questions when requirements are unclear - don't guess or make assumptions"
    parts << "- Confirm your understanding before starting complex work"
    parts << "- If the user is unhappy with your work, offer to fix it - you're here to deliver the best outcome"
    parts << "- Stay on topic - you're here to help with tasks, not for small talk"
    parts << ""
    parts << "**Task iteration:**"
    parts << "- If a user says something like 'that's not quite right', 'can you fix this', or 'try again', treat it as a request to improve your previous work"
    parts << "- When iterating, acknowledge what wasn't right and explain what you're changing"
    parts << "- You may receive follow-up messages in the same conversation - this is normal, like working with a colleague"
    parts << "- Take feedback gracefully and apply it immediately"
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

    # Universal Output Requirement
    parts << "\n## UNIVERSAL OUTPUT REQUIREMENT:"
    parts << "When you have completed your task and are ready to provide the final output, your response MUST be a JSON object with the following schema:"
    parts << "{"
    parts << "  \"summary\": \"Concise, conversational message (2-3 sentences) for the chat interface.\","
    parts << "  \"content\": \"The main payload/result of your task.\","
    parts << "  \"format\": \"markdown\" | \"html\" | \"json\" | \"code\" | \"text\""
    parts << "}"
    parts << "The 'content' field should contain the detailed report, data, or artifact you created."
    parts << "If you are returning structured data (like a campaign object), set format to 'json' and put the data in 'content'."
    parts << "If you are returning a document or report, set format to 'markdown' or 'html' and put the text in 'content'."
    parts << "If you are returning code (e.g. a script), set format to 'code' and put the code in 'content'."
    parts << "Do NOT wrap the JSON in markdown code blocks. Return the raw JSON string only."

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
    collaboration_tool_names = TieredDiscoveryService.agent_collaboration_tool_names.dup
    
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
    
    Rails.logger.info "🔍 Starting tool discovery for prompt: #{@current_prompt.truncate(100)}"
    
    catalog = Tools::ToolCatalog.instance
    discovered = []
    
    # 1. RAG search ToolDefinitions (custom tools) based on task description
    if defined?(ToolDefinition) && ToolDefinition.table_exists?
      begin
        # Search for relevant custom tools
        relevant_custom_tools = ToolDefinition.search_by_similarity(@current_prompt, limit: 5)
        
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
    
    # 2. Semantic search on class-based tools (vectorized in cache)
    begin
      class_tool_results = ClassToolEmbeddingsService.instance.search(@current_prompt, limit: 5)
      
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

  def extract_task_keywords(text)
    return [] if text.blank?
    
    # Common task-related keywords that might indicate tool needs
    keyword_patterns = {
      'weather' => ['weather', 'forecast', 'temperature', 'climate'],
      'search' => ['search', 'find', 'look up', 'research', 'google'],
      'calculate' => ['calculate', 'compute', 'roi', 'math', 'percentage'],
      'data' => ['data', 'database', 'query', 'fetch', 'retrieve'],
      'email' => ['email', 'send', 'message', 'notify'],
      'document' => ['document', 'pdf', 'file', 'read', 'analyze'],
      'api' => ['api', 'integration', 'connect', 'external'],
      'chart' => ['chart', 'graph', 'visualize', 'plot', 'dashboard'],
      'metric' => ['metric', 'analytics', 'statistics', 'report']
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
    config[:model] || context[:agent_plugin].ai_model || 'claude-sonnet-4-5'
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
