# AgentPluginService - Central service for agent plugin discovery, instantiation, and management
#
# This service provides a clean interface for:
# - Discovering agents based on capabilities
# - Finding agents for specific workflow phases
# - Instantiating agent instances with proper configuration
# - Tracking agent executions for analytics
# - Validating agent capabilities
#
# Usage:
#   service = AgentPluginService.new(entity: current_entity, user: current_user)
#   agent_plugin = service.discover_agent(capabilities: ['email_generation'])
#   agent_instance = service.instantiate_agent(agent_plugin, context)
#
class AgentPluginService
  attr_reader :entity, :user

  def initialize(entity: nil, user: nil)
    @entity = entity
    @user = user
  end

  # Discovery Methods

  def discover_agents(capabilities: [], role: nil)
    # Find agents matching required capabilities and optional role
    agents = if capabilities.present?
               AgentPlugin.discover_by_capabilities(capabilities, entity: entity)
             else
               AgentPlugin.active.for_entity(entity)
             end

    agents = agents.by_role(role) if role.present?
    agents.by_priority
  end

  def discover_agent(capabilities: [], role: nil)
    # Find single best agent (highest priority)
    discover_agents(capabilities: capabilities, role: role).first
  end

  def find_agent_for_phase(phase, template: nil)
    # Find the best agent for a specific workflow phase
    agents = AgentPlugin.find_for_phase(phase, template: template, entity: entity)

    # If we have template bindings, prefer those
    if template
      bound_agent = agents.joins(:agent_template_bindings)
                          .where(agent_template_bindings: { workflow_template: template, phase: phase, required: true })
                          .first
      return bound_agent if bound_agent
    end

    # Otherwise return the highest priority agent
    agents.first
  end

  def list_available_agents(filter: {})
    # List all available agents with optional filtering
    agents = AgentPlugin.active.for_entity(entity)

    agents = agents.by_role(filter[:role]) if filter[:role].present?
    agents = agents.where('name ILIKE ?', "%#{filter[:search]}%") if filter[:search].present?

    agents.by_priority
  end

  # Instantiation Methods

  def instantiate_agent(agent_plugin, context = {})
    # Validate agent is available
    unless agent_plugin.status == 'active'
      raise ArgumentError, "Agent #{agent_plugin.name} is not active (status: #{agent_plugin.status})"
    end

    # Validate required tools are available
    validate_required_tools!(agent_plugin)

    # Build execution context
    full_context = build_execution_context(agent_plugin, context)

    # Create execution record
    execution = create_execution_record(agent_plugin, full_context)

    # Instantiate the agent
    begin
      agent_instance = agent_plugin.instantiate(full_context.merge(execution: execution))

      Rails.logger.info "Instantiated agent: #{agent_plugin.name} (#{agent_plugin.slug})"

      agent_instance
    rescue => e
      # Mark execution as failed
      execution.mark_failed!("Failed to instantiate agent: #{e.message}")
      raise
    end
  end

  def instantiate_agent_for_phase(phase, template: nil, context: {})
    # Find and instantiate agent for a phase
    agent_plugin = find_agent_for_phase(phase, template: template)

    unless agent_plugin
      raise ArgumentError, "No agent found for phase: #{phase}"
    end

    instantiate_agent(agent_plugin, context.merge(phase: phase, template: template))
  end

  # Execution Tracking

  def create_execution_record(agent_plugin, context = {})
    AgentPluginExecution.create!(
      agent_plugin: agent_plugin,
      workflow_execution: context[:workflow_execution],
      user: user || context[:user],
      status: 'running',
      input_context: sanitize_context(context),
      started_at: Time.current
    )
  end

  def complete_execution(execution, output = {})
    execution.mark_completed!(output)

    # Update agent's last_activated_at
    execution.agent_plugin.touch(:last_activated_at)

    log_execution_metrics(execution)
  end

  def fail_execution(execution, error_message)
    execution.mark_failed!(error_message)
    log_execution_metrics(execution)
  end

  # Validation Methods

  def validate_agent(agent_plugin)
    errors = []

    # Validate agent class exists
    begin
      agent_plugin.agent_class.constantize
    rescue NameError
      errors << "Invalid agent class: #{agent_plugin.agent_class}"
    end

    # Validate capabilities have proper contracts
    agent_plugin.agent_capabilities.each do |cap|
      unless cap.has_valid_contract?
        errors << "Invalid contract for capability: #{cap.capability_name}"
      end
    end

    # Validate required tools exist
    agent_plugin.agent_tools.required.each do |tool|
      unless tool.tool_available?
        errors << "Required tool not available: #{tool.tool_name}"
      end
    end

    {
      valid: errors.empty?,
      errors: errors
    }
  end

  def validate_required_tools!(agent_plugin)
    missing_tools = []

    agent_plugin.required_tools.each do |tool_name|
      unless Tools::ToolCatalog.instance.tool_exists?(tool_name)
        missing_tools << tool_name
      end
    end

    if missing_tools.any?
      raise ArgumentError, "Agent #{agent_plugin.name} requires missing tools: #{missing_tools.join(', ')}"
    end
  end

  # Analytics Methods

  def agent_performance_stats(agent_plugin, since: 30.days.ago)
    agent_plugin.execution_stats(since: since)
  end

  def entity_agent_usage(since: 30.days.ago)
    # Get usage stats for all agents in this entity
    AgentPluginExecution
      .joins(:agent_plugin)
      .where(agent_plugins: { entity: [nil, entity] })
      .where('agent_plugin_executions.created_at >= ?', since)
      .group('agent_plugins.id', 'agent_plugins.name')
      .select(
        'agent_plugins.id as agent_id',
        'agent_plugins.name as agent_name',
        'COUNT(*) as execution_count',
        'AVG(duration_ms) as avg_duration',
        'SUM(tokens_used) as total_tokens'
      )
      .order('execution_count DESC')
  end

  # Utility Methods

  def agent_exists?(slug)
    AgentPlugin.active.for_entity(entity).exists?(slug: slug)
  end

  def get_agent(slug)
    AgentPlugin.active.for_entity(entity).find_by(slug: slug)
  end

  def clone_agent(source_agent, new_name:, entity: nil)
    # Clone an agent plugin with new name
    cloned = source_agent.dup
    cloned.name = new_name
    cloned.slug = new_name.parameterize.underscore
    cloned.entity = entity || self.entity
    cloned.status = 'draft'
    cloned.save!

    # Clone capabilities
    source_agent.agent_capabilities.each do |cap|
      cloned.agent_capabilities.create!(cap.attributes.except('id', 'agent_plugin_id', 'created_at', 'updated_at'))
    end

    # Clone tools
    source_agent.agent_tools.each do |tool|
      cloned.agent_tools.create!(tool.attributes.except('id', 'agent_plugin_id', 'created_at', 'updated_at'))
    end

    cloned
  end

  private

  def build_execution_context(agent_plugin, context)
    {
      entity: entity,
      user: user,
      agent_plugin: agent_plugin,
      timestamp: Time.current
    }.merge(context)
  end

  def sanitize_context(context)
    # Remove sensitive or non-serializable data
    context.except(:user, :entity, :agent_plugin, :execution).transform_values do |v|
      case v
      when ActiveRecord::Base
        { id: v.id, type: v.class.name }
      else
        v
      end
    end
  end

  def log_execution_metrics(execution)
    # Log to observability system
    ObservabilityEvent.create!(
      entity: entity,
      user: user,
      event_type: 'agent_plugin_execution',
      metadata: {
        agent_plugin_id: execution.agent_plugin_id,
        agent_name: execution.agent_plugin.name,
        status: execution.status,
        duration_ms: execution.duration_ms,
        tokens_used: execution.tokens_used,
        workflow_execution_id: execution.workflow_execution_id
      }
    )
  rescue => e
    Rails.logger.warn "Failed to log execution metrics: #{e.message}"
  end
end
