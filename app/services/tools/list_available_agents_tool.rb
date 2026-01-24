# frozen_string_literal: true

module Tools
  # DEPRECATED: Use find_best_agent instead
  # This tool now just calls find_best_agent for backwards compatibility
  class ListAvailableAgentsTool < BaseTool
    # DEPRECATED: Agents have been removed from the platform.
    
    def self.metadata
      {
        name: 'list_available_agents',
        description: 'DEPRECATED - DO NOT USE. Agents have been removed. Use discover_tools instead.',
        category: 'deprecated',
        deprecated: true,
        input_schema: {
          type: 'object',
          properties: {
            task_description: {
              type: 'string',
              description: 'Description of the task - will be passed to find_best_agent'
            },
            max_results: {
              type: 'integer',
              description: 'Maximum number of agents to return',
              default: 5
            }
          },
          required: ['task_description']
        }
      }
    end

    def self.read_only?
      true
    end

    def execute(args = {})
      args = args.with_indifferent_access
      
      Rails.logger.warn "⚠️ list_available_agents is deprecated - redirecting to find_best_agent"
      
      # Redirect to find_best_agent
      find_tool = FindBestAgentTool.new(user: user, entity: entity, session_id: @session_id)
      result = find_tool.execute({
        task_description: args[:task_description],
        top_n: args[:max_results] || 5
      })
      
      # Transform response to match old format for backwards compatibility
      if result[:success] && result[:best_agent]
        agents = [result[:best_agent]]
        agents += result[:alternatives] if result[:alternatives]
        
        success_response(
          agents: agents,
          total_found: agents.size,
          message: "⚠️ DEPRECATED: Use find_best_agent instead of list_available_agents",
          next_step: result[:next_step]
        )
      else
        result
      end
    rescue => e
      error_response("Error: #{e.message}")
    end
  end
end
