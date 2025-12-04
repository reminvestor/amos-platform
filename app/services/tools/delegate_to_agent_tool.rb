module Tools
  class DelegateToAgentTool < BaseTool
    def self.metadata
      {
        name: "delegate_to_agent",
        description: "Delegate a complex task directly to a specialized agent. The agent will handle the task independently and communicate progress back through Scout.",
        category: "task_management",
        input_schema: {
          type: "object",
          properties: {
            agent_type: {
              type: "string",
              description: "The type of specialist agent needed (e.g., 'landing_page_agent', 'email_agent', 'integration_agent', 'data_agent')"
            },
            task_description: {
              type: "string",
              description: "Clear description of what the agent should do"
            },
            context: {
              type: "object",
              description: "Any additional context or requirements for the agent",
              properties: {}
            }
          },
          required: [ "agent_type", "task_description" ]
        }
      }
    end

    def execute(args)
      Rails.logger.info "🤝 Delegating to agent: #{args['agent_type']}"

      agent_type = args["agent_type"]
      task_description = args["task_description"]
      additional_context = args["context"] || {}

      # Create execution record for the agent plugin
      execution = AgentPluginExecution.create!(
        agent_plugin: find_agent_plugin(agent_type),
        user: user,
        status: 'running',
        started_at: Time.current,
        model_id: context[:model_preference] || 'claude-3-5-sonnet',
        input_context: {
          task: task_description,
          session_id: context[:session_id] || SecureRandom.uuid,
          additional_context: additional_context
        }
      )
      
      job_id = execution.id # Use execution ID as job ID for compatibility

      # Queue the generic AgentPluginExecutionJob
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
        type: "agent_delegated",
        agent: agent_type,
        job_id: execution.id,
        message: "Task delegated to #{find_agent_plugin(agent_type).name}"
      })
      
      # Automatically load the Tasks canvas if we have a session_id
      if context[:session_id]
        # Check if tasks canvas is already loaded
        unless current_canvas_is_tasks?
          Rails.logger.info "[DelegateToAgentTool] Auto-loading Tasks canvas"
          ScoutChannel.broadcast_to(context[:session_id], {
            type: 'load_canvas',
            canvas_name: 'scheduled_tasks',
            canvas_data: { session_id: context[:session_id] }
          })
        end
        
        # Broadcast job creation to task monitor
        ScoutChannel.broadcast_to(context[:session_id], {
          type: 'task_progress',
          job_id: execution.id,
          status: 'created',
          agent_type: find_agent_plugin(agent_type).slug,
          message: "Starting #{find_agent_plugin(agent_type).name}..."
        })
      end

      {
        success: true,
        job_id: execution.id,
        agent_type: agent_type
      }
    rescue => e
      Rails.logger.error "DelegateToAgentTool error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      {
        success: false,
        error: "Failed to delegate to agent: #{e.message}"
      }
    end
    
    private
    
    def find_agent_plugin(slug_or_name)
      # Normalize input
      key = slug_or_name.to_s.strip.downcase
      
      # Try exact slug match first
      plugin = AgentPlugin.active.find_by(slug: key)
      return plugin if plugin
      
      # Try mapping old system names to new slugs
      # Mapping table: old_name => new_slug
      mapping = {
        'landing_page_agent' => 'ai_landing_page_creator',
        'email_agent' => 'email_sequence_architect', # or sales_email_generator
        'integration_agent' => 'integration_architect',
        'data_agent' => 'data_manager', # Assumption
        'analytics_agent' => 'campaign_optimizer',
        # Agent/Tool creation agents
        'agent_builder' => 'agent_architect',
        'agent_creator' => 'agent_architect',
        'tool_creator' => 'tool_builder',
        'tool_builder_agent' => 'tool_builder'
      }
      
      if mapped_slug = mapping[key]
        plugin = AgentPlugin.active.find_by(slug: mapped_slug)
        return plugin if plugin
      end
      
      # Try fuzzy match on name
      plugin = AgentPlugin.active.where("LOWER(name) LIKE ?", "%#{key.gsub('_', ' ')}%").first
      return plugin if plugin
      
      # Fallback: Raise error so we don't fail silently
      raise "Could not find active agent plugin for '#{slug_or_name}'"
    end
    
    def current_canvas_is_tasks?
      # Check if the current canvas context shows tasks canvas is loaded
      return false unless @context[:current_canvas]
      %w[scheduled_tasks parallel_tasks].include?(@context[:current_canvas][:type])
    end
  end
end
