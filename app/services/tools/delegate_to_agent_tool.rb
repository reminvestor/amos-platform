module Tools
  class DelegateToAgentTool < BaseTool
    def self.metadata
      {
        name: "delegate_to_agent",
        description: <<~DESC.strip,
          Delegate a task to a specialized agent. 
          
          RECOMMENDED: Use propose_task_to_agent FIRST to check if the agent can handle the task,
          then pass the proposal_id here. This ensures the agent has agreed to the task.
          
          If no proposal_id is provided, the system will auto-evaluate but may reject the task.
        DESC
        category: "task_management",
        input_schema: {
          type: "object",
          properties: {
            agent_type: {
              type: "string",
              description: "Agent identifier - can be exact slug (e.g., 'analytics_agent'), descriptive term, or capability name."
            },
            task_description: {
              type: "string",
              description: "Clear description of what the agent should do"
            },
            proposal_id: {
              type: "integer",
              description: "ID of an accepted proposal from propose_task_to_agent. RECOMMENDED for reliable delegation."
            },
            tools_likely_needed: {
              type: "array",
              items: { type: "string" },
              description: "Tools the agent will need (used for auto-handshake if no proposal_id)"
            },
            skip_handshake: {
              type: "boolean",
              description: "Skip capability check (not recommended, may fail). Default: false"
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
      proposal_id = args["proposal_id"]
      tools_needed = args["tools_likely_needed"] || []
      skip_handshake = args["skip_handshake"] == true
      additional_context = args["context"] || {}
      
      # Find the agent first
      agent_plugin = find_agent_plugin(agent_type)
      
      # Handle handshake protocol
      proposal = nil
      if proposal_id.present?
        # Use existing proposal
        proposal = AgentTaskProposal.find_by(id: proposal_id, receiving_agent: agent_plugin)
        unless proposal&.accepted?
          return {
            success: false,
            error: "Proposal #{proposal_id} not found or not accepted. Use propose_task_to_agent first."
          }
        end
        Rails.logger.info "✅ Using pre-approved proposal #{proposal_id}"
      elsif !skip_handshake
        # Auto-handshake: create and evaluate proposal
        proposal = AgentTaskProposal.create!(
          proposing_agent: nil,
          receiving_agent: agent_plugin,
          entity: entity,
          user: user,
          task_description: task_description,
          tools_needed: tools_needed,
          status: 'proposed'
        )
        
        evaluation = proposal.evaluate_capability
        
        if evaluation[:accepted]
          proposal.accept!(confidence: evaluation[:confidence], details: evaluation[:details])
          Rails.logger.info "✅ Auto-handshake accepted with #{(evaluation[:confidence] * 100).round}% confidence"
        else
          proposal.reject!(
            reason: evaluation[:reason],
            missing_tools: evaluation[:missing_tools],
            missing_capabilities: evaluation[:missing_capabilities],
            alternatives: evaluation[:alternatives]
          )
          
          return {
            success: false,
            error: "Agent '#{agent_plugin.name}' rejected the task",
            reason: evaluation[:reason],
            missing_tools: evaluation[:missing_tools],
            suggested_alternatives: evaluation[:alternatives],
            recommendation: "Use propose_task_to_agent to find a capable agent, or add missing tools."
          }
        end
      else
        Rails.logger.warn "⚠️ Skipping handshake for delegation to #{agent_plugin.slug}"
      end
      
      # Include attached files from the main context so agents can access uploaded documents
      if context[:attached_files].present?
        additional_context[:attached_files] = context[:attached_files]
        Rails.logger.info "📎 Passing #{context[:attached_files].length} attached files to agent"
      end

      # Create execution record for the agent plugin
      execution = AgentPluginExecution.create!(
        agent_plugin: agent_plugin,
        user: user,
        status: 'running',
        started_at: Time.current,
        model_id: context[:model_preference] || 'qwen3-next-80b',
        input_context: {
          task: task_description,
          session_id: context[:session_id] || SecureRandom.uuid,
          entity_id: entity.id,  # Pass entity explicitly for agent context
          additional_context: additional_context,
          attached_files: context[:attached_files],
          proposal_id: proposal&.id
        }
      )
      
      # Link proposal to execution
      if proposal
        proposal.start_execution!(execution: execution)
      end
      
      job_id = execution.id # Use execution ID as job ID for compatibility

      # Queue the generic AgentPluginExecutionJob
      # IMPORTANT: Pass entity_id, not entity object, because Entity can't be serialized by ActiveJob
      AgentPluginExecutionJob.perform_later(
        execution.id,
        task_description,
        {
          entity_id: entity.id,
          user_id: user.id,
          session_id: context[:session_id],
          model_preference: context[:model_preference],
          additional_context: additional_context,
          attached_files: context[:attached_files]
        }
      )
        
      # Notify about the delegation
      agent_name = agent_plugin.name
      @progress_callback&.call({
        type: "agent_delegated",
        agent: agent_type,
        job_id: execution.id,
        message: "Task delegated to #{agent_name}"
      })
      
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
        proposal_id: proposal&.id,
        handshake_confidence: proposal&.confidence,
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

