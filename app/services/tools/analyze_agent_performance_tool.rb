# frozen_string_literal: true

module Tools
  # Analyzes agent performance and identifies improvement opportunities
  class AnalyzeAgentPerformanceTool < BaseTool
    # DEPRECATED: Agent performance analysis is no longer used. The agent system has been removed.
    
    def self.metadata
      {
        name: 'analyze_agent_performance',
        description: <<~DESC.strip,
          DEPRECATED - DO NOT USE. The agent system has been removed.
          Amos now handles all tasks directly.
        DESC
        category: 'deprecated',
        input_schema: {
          type: 'object',
          properties: {
            agent_slug: {
              type: 'string',
              description: "The agent's slug (e.g., 'module_architect'). Leave empty for all agents."
            },
            include_recommendations: {
              type: 'boolean',
              description: 'Include evolution recommendations (default: true)'
            }
          },
          required: []
        }
      }
    end

    def self.read_only?
      true
    end

    def execute(args)
      log_execution(args)

      agent_slug = get_arg(args, :agent_slug)
      include_recommendations = get_arg(args, :include_recommendations, true)

      evolution = Agents::EvolutionService.new(entity: entity)

      if agent_slug.present?
        agent = AgentPlugin.find_by(slug: agent_slug, status: 'active')
        return error_response("Agent '#{agent_slug}' not found") unless agent

        analysis = evolution.analyze_agent(agent)
        
        success_response(
          agent: analysis[:agent],
          performance: analysis[:performance],
          evolution_score: analysis[:evolution_score],
          skill_gaps: analysis[:skill_gaps],
          evolution_opportunities: include_recommendations ? analysis[:evolution_opportunities] : nil,
          training_recommendations: include_recommendations ? analysis[:recommended_training] : nil
        )
      else
        # Analyze all agents
        report = evolution.analyze_all_agents

        success_response(
          timestamp: report[:timestamp],
          agents_analyzed: report[:agents_analyzed],
          top_performers: report[:top_performers].map { |a| 
            { 
              slug: a[:agent][:slug], 
              name: a[:agent][:name],
              success_rate: a[:performance][:success_rate],
              evolution_score: a[:evolution_score]
            }
          },
          needs_improvement: report[:needs_improvement].map { |a|
            {
              slug: a[:agent][:slug],
              name: a[:agent][:name],
              success_rate: a[:performance][:success_rate],
              issues: a[:skill_gaps].count
            }
          },
          system_recommendations: include_recommendations ? report[:system_recommendations] : nil
        )
      end
    rescue => e
      Rails.logger.error "[AnalyzeAgentPerformance] Error: #{e.message}"
      error_response("Failed to analyze agent performance: #{e.message}")
    end
  end
end





