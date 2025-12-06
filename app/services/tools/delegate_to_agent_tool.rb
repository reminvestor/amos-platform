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
      key = slug_or_name.to_s.strip
      normalized_key = key.downcase.gsub(/[_\s]+/, '_')
      
      Rails.logger.info "[DelegateToAgent] Searching for agent: '#{key}'"
      
      # 1. Try exact slug match first (fastest)
      plugin = AgentPlugin.active.find_by(slug: normalized_key)
      if plugin
        Rails.logger.info "[DelegateToAgent] Found by exact slug: #{plugin.name}"
        return plugin
      end
      
      # 2. Try slug with common variations
      variations = [
        normalized_key,
        normalized_key.gsub('_agent', ''),
        "#{normalized_key}_agent",
        normalized_key.gsub('_', '')
      ].uniq
      
      variations.each do |slug|
        plugin = AgentPlugin.active.find_by(slug: slug)
        if plugin
          Rails.logger.info "[DelegateToAgent] Found by slug variation '#{slug}': #{plugin.name}"
          return plugin
        end
      end
      
      # 3. Search by triggers in configuration (agents define what tasks they handle)
      search_terms = key.downcase.split(/[\s_]+/)
      AgentPlugin.active.find_each do |agent|
        triggers = agent.configuration&.dig('triggers') || []
        if triggers.any? { |trigger| search_terms.any? { |term| trigger.downcase.include?(term) } }
          Rails.logger.info "[DelegateToAgent] Found by trigger match: #{agent.name}"
          return agent
        end
      end
      
      # 4. Search by capabilities
      AgentPlugin.active.joins(:agent_capabilities).find_each do |agent|
        cap_names = agent.capability_names.map(&:downcase)
        if search_terms.any? { |term| cap_names.any? { |cap| cap.include?(term) } }
          Rails.logger.info "[DelegateToAgent] Found by capability match: #{agent.name}"
          return agent
        end
      end
      
      # 5. Fuzzy match on name/description
      search_pattern = "%#{key.gsub(/[_\s]+/, '%')}%"
      plugin = AgentPlugin.active.where("LOWER(name) LIKE ? OR LOWER(description) LIKE ?", 
                                        search_pattern.downcase, search_pattern.downcase).first
      if plugin
        Rails.logger.info "[DelegateToAgent] Found by fuzzy name/description: #{plugin.name}"
        return plugin
      end
      
      # 6. Semantic/vector search as last resort (if embeddings exist)
      begin
        results = AgentPlugin.search_by_similarity(key, limit: 1)
        if results.any?
          plugin = results.first
          Rails.logger.info "[DelegateToAgent] Found by semantic search: #{plugin.name}"
          return plugin
        end
      rescue => e
        Rails.logger.warn "[DelegateToAgent] Semantic search failed: #{e.message}"
      end
      
      # 7. List available agents in error message to help debugging
      available = AgentPlugin.active.pluck(:slug, :name).map { |s, n| "#{s} (#{n})" }.join(", ")
      raise "Could not find agent for '#{slug_or_name}'. Available agents: #{available}"
    end
    
    def current_canvas_is_tasks?
      # Check if the current canvas context shows tasks canvas is loaded
      return false unless @context[:current_canvas]
      %w[scheduled_tasks parallel_tasks].include?(@context[:current_canvas][:type])
    end
  end
end
