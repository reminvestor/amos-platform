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

    result[:content]
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

    parts.join("\n")
  end

  def execute_with_bedrock(prompt, context_data)
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
        # Create the tool result message
        # We assume the last message in history was the tool_use for ask_user
        tool_use_id = find_last_tool_use_id(messages, 'ask_user')
        
        if tool_use_id
          tool_result_message = {
            role: 'user',
            content: [
              {
                toolResult: {
                  toolUseId: tool_use_id,
                  content: [
                    { text: input_request.response_content }
                  ],
                  status: "success"
                }
              }
            ]
          }
          messages << tool_result_message
          Rails.logger.info "📝 Resuming execution with user answer: #{input_request.response_content.truncate(50)}"
        end
      end
    end

    begin
      # Call BedrockService with the correct method
      # This handles the turn loop internally for simple tools,
      # but we need to catch the suspension for ask_user
      content = bedrock_service.send_message_converse(
        system_prompt_text,
        messages,
        model: model_name,
        max_tokens: config[:max_tokens] || 4096,
        temperature: config[:temperature] || 0.7,
        tools: tools
      )

      # Return in consistent format
      {
        content: content,
        usage: nil # BedrockService handles usage tracking internally
      }
    rescue Tools::AskUserTool::ExecutionSuspended => e
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
      
      raise e
    end

  rescue => e
    Rails.logger.error "StandardPluginExecutor failed: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")

    # Return error in consistent format
    {
      content: "Error executing agent: #{e.message}",
      error: true,
      error_message: e.message
    }
  end

  def get_available_tools
    return [] unless context[:agent_plugin]

    agent_plugin = context[:agent_plugin]

    # Get tool names from agent configuration
    tool_names = agent_plugin.agent_tools.pluck(:tool_name)
    
    # Always add 'ask_user' for interactive agents
    tool_names << 'ask_user' unless tool_names.include?('ask_user')
    
    return [] if tool_names.empty?

    # Load tool definitions from ToolCatalog
    catalog = Tools::ToolCatalog.instance
    tool_names.filter_map { |name| catalog.get_tool_definition(name) }
  rescue => e
    Rails.logger.warn "Failed to load tools for agent: #{e.message}"
    []
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
          if block[:toolUse] && block[:toolUse][:name] == tool_name
            return block[:toolUse][:toolUseId]
          end
        end
      end
    end
    nil
  end
end
