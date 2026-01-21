# frozen_string_literal: true

module Tools
  # Proposes a task to an agent and gets their acceptance/rejection
  # This is the handshake protocol - agents must agree to tasks before execution
  class ProposeTaskToAgentTool < BaseTool
    def self.metadata
      {
        name: 'propose_task_to_agent',
        description: <<~DESC.strip,
          Propose a task to an agent and check if they can handle it BEFORE delegating.
          This is the handshake protocol - the agent evaluates their capabilities and 
          accepts or rejects the task. Always use this before delegate_to_agent to avoid
          assigning tasks to agents that cannot complete them.
          
          Returns:
          - If ACCEPTED: confidence score and confirmation the agent can proceed
          - If REJECTED: reason why, missing tools/capabilities, and suggested alternatives
        DESC
        category: 'agent_management',
        input_schema: {
          type: 'object',
          properties: {
            agent_slug: {
              type: 'string',
              description: "The slug of the agent to propose the task to (e.g., 'module_architect', 'tool_builder')"
            },
            task_description: {
              type: 'string',
              description: 'Clear description of what the agent needs to do'
            },
            task_type: {
              type: 'string',
              enum: AgentTaskProposal::TASK_TYPES,
              description: 'Category of task for routing and analytics'
            },
            tools_likely_needed: {
              type: 'array',
              items: { type: 'string' },
              description: 'Tools the agent will probably need (e.g., ["update_object", "get_data"])'
            },
            object_types: {
              type: 'array',
              items: { type: 'string' },
              description: 'Object types involved (e.g., ["multi_armed_bandit_testing", "landing_page"])'
            },
            required_capabilities: {
              type: 'array',
              items: { type: 'string' },
              description: 'Specific capabilities needed (e.g., ["update_records", "fix_modules"])'
            },
            context: {
              type: 'object',
              description: 'Additional context to help the agent evaluate'
            }
          },
          required: %w[agent_slug task_description]
        }
      }
    end

    def execute(args)
      log_execution(args)

      agent_slug = get_arg(args, :agent_slug)
      task_description = get_arg(args, :task_description)
      task_type = get_arg(args, :task_type, 'custom')
      tools_needed = get_arg(args, :tools_likely_needed, [])
      object_types = get_arg(args, :object_types, [])
      required_capabilities = get_arg(args, :required_capabilities, [])
      context = get_arg(args, :context, {})

      # Validate required args
      if error = validate_required_args(args, %i[agent_slug task_description])
        return error
      end

      # Find the agent
      agent = find_agent(agent_slug)
      return error_response("Agent '#{agent_slug}' not found", available_agents: list_available_agents) unless agent

      # Create the proposal
      proposal = AgentTaskProposal.create!(
        proposing_agent: nil, # Scout/Amos
        receiving_agent: agent,
        entity: entity,
        user: user,
        task_description: task_description,
        task_type: task_type,
        tools_needed: tools_needed,
        object_types: object_types,
        required_capabilities: required_capabilities,
        context: context,
        status: 'proposed'
      )

      # Evaluate the proposal
      evaluation = proposal.evaluate_capability

      if evaluation[:accepted]
        proposal.accept!(
          confidence: evaluation[:confidence],
          details: evaluation[:details]
        )

        success_response(
          proposal_id: proposal.id,
          accepted: true,
          agent_slug: agent.slug,
          agent_name: agent.name,
          confidence: evaluation[:confidence],
          message: evaluation[:message],
          details: evaluation[:details],
          next_step: "Task accepted! Now use delegate_to_agent with proposal_id: #{proposal.id}"
        )
      else
        proposal.reject!(
          reason: evaluation[:reason],
          missing_tools: evaluation[:missing_tools],
          missing_capabilities: evaluation[:missing_capabilities],
          alternatives: evaluation[:alternatives]
        )

        # Find better alternatives with success rates
        alternatives_with_stats = find_alternatives_with_stats(
          task_type: task_type,
          tools_needed: tools_needed,
          object_types: object_types
        )

        error_response(
          "Agent '#{agent.name}' cannot accept this task",
          proposal_id: proposal.id,
          accepted: false,
          agent_slug: agent.slug,
          reason: evaluation[:reason],
          missing_tools: evaluation[:missing_tools],
          missing_capabilities: evaluation[:missing_capabilities],
          suggested_alternatives: alternatives_with_stats,
          recommendation: build_recommendation(alternatives_with_stats)
        )
      end
    rescue => e
      Rails.logger.error "[ProposeTask] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      error_response("Failed to propose task: #{e.message}")
    end

    private

    def find_agent(slug)
      AgentPlugin.find_by(slug: slug, status: 'active') ||
        AgentPlugin.find_by(name: slug, status: 'active') ||
        AgentPlugin.where(status: 'active').where('slug LIKE ?', "%#{slug}%").first
    end

    def list_available_agents
      AgentPlugin.where(status: 'active')
        .pluck(:slug, :name, :description)
        .map { |s, n, d| { slug: s, name: n, description: d&.truncate(80) } }
    end

    def find_alternatives_with_stats(task_type:, tools_needed:, object_types:)
      catalog = Tools::ToolCatalog.instance
      
      AgentPlugin.where(status: 'active').map do |agent|
        agent_tools = agent.agent_tools.pluck(:tool_name)
        tools_match = (agent_tools & tools_needed).length
        
        # Calculate historical success rate
        success_rate = AgentTaskProposal.success_rate_for(agent: agent, task_type: task_type)
        
        {
          slug: agent.slug,
          name: agent.name,
          tools_available: agent_tools.length,
          tools_match: tools_match,
          tools_needed: tools_needed.length,
          match_percentage: tools_needed.present? ? (tools_match.to_f / tools_needed.length * 100).round : 0,
          historical_success_rate: (success_rate * 100).round,
          recommendation_score: calculate_recommendation_score(tools_match, tools_needed.length, success_rate)
        }
      end
      .select { |a| a[:tools_match] > 0 || a[:historical_success_rate] > 50 }
      .sort_by { |a| -a[:recommendation_score] }
      .first(5)
    end

    def calculate_recommendation_score(tools_match, tools_needed, success_rate)
      tool_score = tools_needed > 0 ? (tools_match.to_f / tools_needed) * 50 : 25
      history_score = success_rate * 50
      tool_score + history_score
    end

    def build_recommendation(alternatives)
      return "No suitable alternatives found. Consider creating required tools first." if alternatives.empty?

      best = alternatives.first
      if best[:match_percentage] >= 80
        "Try '#{best[:slug]}' - #{best[:match_percentage]}% tool match, #{best[:historical_success_rate]}% historical success"
      elsif best[:historical_success_rate] >= 70
        "Try '#{best[:slug]}' - has #{best[:historical_success_rate]}% historical success rate for similar tasks"
      else
        "Best available: '#{best[:slug]}' with #{best[:match_percentage]}% tool match. May need to create missing tools."
      end
    end
  end
end





