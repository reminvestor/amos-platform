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

    Rails.logger.info "StandardPluginExecutor running with prompt: #{prompt.truncate(100)}"

    # Build the full prompt with configuration
    full_prompt = build_full_prompt(prompt, merged_context)

    # Execute via Bedrock
    result = execute_with_bedrock(full_prompt, merged_context)

    # Track token usage if we have an execution record
    if execution && result[:usage]
      execution.add_tokens(result[:usage][:total_tokens])
    end

    result[:content]
  end

  # Goal-based execution (for workflow phases)
  def achieve_goal(goal, context_data = {})
    goal_prompt = <<~PROMPT
      Goal: #{goal}

      Context:
      #{JSON.pretty_generate(context_data)}

      Please achieve this goal based on your capabilities and the provided context.
    PROMPT

    run(goal_prompt, context_data)
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

  def build_full_prompt(user_prompt, context_data)
    parts = []

    # Add system prompt
    parts << system_prompt if system_prompt.present?

    # Add configuration context
    if config.present?
      parts << "\nConfiguration:"
      parts << JSON.pretty_generate(config)
    end

    # Add capabilities
    if capabilities.present?
      parts << "\nYour capabilities:"
      capabilities.each { |cap| parts << "- #{cap}" }
    end

    # Add user prompt
    parts << "\n#{user_prompt}"

    parts.join("\n")
  end

  def execute_with_bedrock(prompt, context_data)
    # Determine which model to use
    model_name = get_model_name

    bedrock_service = BedrockService.new(
      entity: context[:entity],
      user: context[:user],
      model: model_name
    )

    # Get available tools for this agent
    tools = get_available_tools

    # Build bedrock call options
    call_options = {
      prompt: prompt,
      max_tokens: config[:max_tokens] || 4096,
      temperature: config[:temperature] || 0.7
    }.merge(get_model_config)

    # Execute with tool calling if tools are available
    if tools.present?
      result = bedrock_service.call_with_tools(
        **call_options,
        tools: tools,
        context: context_data
      )
    else
      # Simple text generation without tools
      result = bedrock_service.call(**call_options)
    end

    result
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

    # Agent's model preference, or fall back to config
    context[:agent_plugin].model_name || config[:model] || 'claude-sonnet-4'
  end

  def get_model_config
    return {} unless context[:agent_plugin]

    # Additional model-specific configuration
    context[:agent_plugin].model_config || {}
  end
end
