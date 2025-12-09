module Tools
  class DelegateToAgentTool < BaseTool
    def self.metadata
      {
        name: "delegate_to_agent",
        description: "Delegate a task to a specialized agent. Uses intelligent matching to find the right agent by slug, triggers, capabilities, or semantic search.",
        category: "task_management",
        input_schema: {
          type: "object",
          properties: {
            agent_type: {
              type: "string",
              description: "Agent identifier - can be exact slug (e.g., 'analytics_agent'), descriptive term (e.g., 'data analysis', 'stripe sales'), or capability name. The system will find the best matching agent."
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
      
      agent_plugin = find_agent_plugin(agent_type)
      agent_name = agent_plugin.name
      
      # Broadcast job creation to task monitor (no auto canvas load - user stays on current view)
      if context[:session_id]
        ScoutChannel.broadcast_to(context[:session_id], {
          type: 'task_progress',
          job_id: execution.id,
          status: 'created',
          agent_type: agent_plugin.slug,
          message: "Starting #{agent_name}..."
        })
      end

      # Build a helpful user message
      user_message = <<~MSG.strip
        ✅ **#{agent_name}** is now working on your request!

        **What's happening:**
        - The agent is processing your task in the background
        - You can continue chatting with me while it works
        
        **How to track progress:**
        - Check the **Work Items** inbox (📥) for updates
        - If the agent needs more information, you'll see a notification badge
        
        **Task:** #{task_description.truncate(100)}
      MSG

      {
        success: true,
        job_id: execution.id,
        agent_type: agent_type,
        agent_name: agent_name,
        message: user_message
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
      key = slug_or_name.to_s.strip
      normalized_key = key.downcase.gsub(/[_\s]+/, '_')
      
      # 1. Exact slug match - scoped to this entity (or system-wide)
      plugin = AgentPlugin.active.for_entity(entity).find_by(slug: normalized_key)
      return plugin if plugin
      
      # 2. Semantic search (scales to millions via pgvector) - scoped to entity
      results = AgentPlugin.search_by_similarity(key, limit: 1, entity: entity)
      return results.first if results.any?
      
      # No match - show available agents for this entity
      available = AgentPlugin.active.for_entity(entity).limit(10).pluck(:slug).join(", ")
      raise "Could not find agent for '#{slug_or_name}'. Available: #{available}"
    end
    
    def current_canvas_is_tasks?
      # Check if the current canvas context shows tasks canvas is loaded
      return false unless @context[:current_canvas]
      %w[scheduled_tasks parallel_tasks].include?(@context[:current_canvas][:type])
    end
  end
end

