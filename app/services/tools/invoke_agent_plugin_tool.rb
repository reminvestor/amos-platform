module Tools
  class InvokeAgentPluginTool < BaseTool
    # DEPRECATED: Agent plugins are no longer used. Amos handles all tasks directly.
    
    def self.metadata
      {
        name: "invoke_agent_plugin",
        description: "DEPRECATED - DO NOT USE. Agent plugins have been removed. Amos now handles all tasks directly using available tools.",
        category: "deprecated",
        input_schema: {
          type: "object",
          properties: {
            agent_identifier: {
              type: "string",
              description: "The agent's slug, name, or a description to match. Examples: 'web_research_agent', 'web research', 'research agent'"
            },
            task_description: {
              type: "string",
              description: "Clear description of what the agent should do"
            },
            capabilities: {
              type: "array",
              description: "Optional: specific capabilities needed (e.g., ['web_research', 'content_analysis']). Use this to find agents by what they can do.",
              items: {
                type: "string"
              }
            },
            context: {
              type: "object",
              description: "Any additional context or requirements for the agent",
              properties: {}
            }
          },
          required: ["agent_identifier", "task_description"]
        }
      }
    end

    def execute(args)
      Rails.logger.info "🔍 Discovering agent plugin: #{args['agent_identifier']}"

      agent_identifier = args["agent_identifier"]
      task_description = args["task_description"]
      capabilities = args["capabilities"] || []
      additional_context = args["context"] || {}

      begin
        # Discover the agent plugin
        agent_plugin = discover_agent_plugin(agent_identifier, capabilities)

        unless agent_plugin
          return error_response(
            message: "No agent found matching '#{agent_identifier}'. Available agents: #{list_available_agents}",
            data: { available_agents: list_available_agents }
          )
        end

        Rails.logger.info "✅ Found agent plugin: #{agent_plugin.name} (#{agent_plugin.slug})"

        # Create execution record
        execution = AgentPluginExecution.create!(
          agent_plugin: agent_plugin,
          user: user,
          workflow_execution_id: context[:workflow_execution_id],
          status: 'running',
          input_context: {
            task: task_description,
            agent_identifier: agent_identifier,
            capabilities: capabilities,
            additional_context: additional_context
          }
        )

        # Queue the execution job
        AgentPluginExecutionJob.perform_later(
          execution.id,
          task_description,
          {
            entity: entity,
            user_id: user.id,
            session_id: context[:session_id],
            model_preference: context[:model_preference],
            additional_context: additional_context
          }
        )

        # Notify about the delegation
        @progress_callback&.call({
          type: "agent_plugin_delegated",
          agent: agent_plugin.name,
          agent_slug: agent_plugin.slug,
          execution_id: execution.id,
          message: "Task delegated to #{agent_plugin.name}"
        })

        # Broadcast job creation to task monitor (no auto canvas load - user stays on current view)
        if context[:session_id]
          ScoutChannel.broadcast_to(context[:session_id], {
            type: 'task_progress',
            job_id: execution.id,
            status: 'queued',
            agent_type: agent_plugin.slug,
            message: "Starting #{agent_plugin.name}..."
          })
        end

        success_response(
          message: "Successfully delegated task to #{agent_plugin.name}. The agent is now working on: #{task_description.truncate(100)}",
          data: {
            execution_id: execution.id,
            agent_name: agent_plugin.name,
            agent_slug: agent_plugin.slug,
            capabilities: agent_plugin.capability_names,
            status: 'queued'
          }
        )
      rescue => e
        Rails.logger.error "InvokeAgentPluginTool error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")

        error_response(
          message: "Failed to invoke agent plugin: #{e.message}",
          data: { error: e.message }
        )
      end
    end

    private

    def discover_agent_plugin(identifier, capabilities = [])
      # Get entity-scoped and system-wide active agents
      scope = AgentPlugin.active.for_entity(entity)

      # Strategy 1: Exact slug match
      agent = scope.find_by(slug: identifier.to_s.parameterize.underscore)
      return agent if agent

      # Strategy 2: Exact name match (case-insensitive)
      agent = scope.where("LOWER(name) = ?", identifier.to_s.downcase).first
      return agent if agent

      # Strategy 3: Partial name match
      agent = scope.where("LOWER(name) LIKE ?", "%#{identifier.to_s.downcase}%").first
      return agent if agent

      # Strategy 4: Capability-based discovery
      if capabilities.any?
        agent = AgentPlugin.discover_by_capabilities(capabilities, entity: entity).first
        return agent if agent
      end

      # Strategy 5: Description search (last resort)
      scope.where("LOWER(description) LIKE ?", "%#{identifier.to_s.downcase}%").first
    end

    def list_available_agents
      AgentPlugin.active.for_entity(entity).pluck(:name, :slug).map do |name, slug|
        "#{name} (#{slug})"
      end.join(", ")
    end

    def current_canvas_is_work_inbox?
      return false unless @context[:current_canvas]
      canvas_type = @context[:current_canvas][:type]
      # Consider both work_inbox and parallel_tasks as "task viewing" canvases
      canvas_type.in?(['work_inbox', 'parallel_tasks', 'scheduled_tasks'])
    end
  end
end
