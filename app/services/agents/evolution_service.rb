# frozen_string_literal: true

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                           ⚠️ DEPRECATED ⚠️                                  ║
# ╠════════════════════════════════════════════════════════════════════════════╣
# ║ This file is DEPRECATED as of 2026-01-24.                                   ║
# ║                                                                             ║
# ║ With the Plugin Injection architecture, evolution is now handled by:        ║
# ║ - LoadoutHealthMonitor - monitors loadout health and applies fixes           ║
# ║ - LoadoutOptimizationService - suggests and applies improvements             ║
# ║                                                                             ║
# ║ The ticketing system for PLATFORM evolution is still valid, but goes to     ║
# ║ PlatformEvolutionTicket for code-level changes (not user-buildable).        ║
# ║                                                                             ║
# ║ DO NOT USE THIS FILE FOR NEW CODE.                                          ║
# ╚════════════════════════════════════════════════════════════════════════════╝

module Agents
  # Agent Evolution Service: Analyzes agent performance and triggers improvements
  # DEPRECATED: Use LoadoutHealthMonitor and LoadoutOptimizationService instead
  class EvolutionService
    attr_reader :entity

    def initialize(entity:)
      @entity = entity
    end

    # Generate evolution report for an agent
    def analyze_agent(agent)
      proposals = AgentTaskProposal.where(receiving_agent: agent, entity: entity)
        .where('created_at > ?', 30.days.ago)

      {
        agent: {
          slug: agent.slug,
          name: agent.name,
          role: agent.role,
          version: agent.version,
          tools: agent.agent_tools.pluck(:tool_name)
        },
        performance: calculate_performance_metrics(proposals),
        skill_gaps: identify_skill_gaps(proposals, agent),
        evolution_opportunities: find_evolution_opportunities(proposals, agent),
        recommended_training: generate_training_recommendations(proposals, agent),
        evolution_score: calculate_evolution_score(proposals, agent)
      }
    end

    # Generate evolution report for all agents
    def analyze_all_agents
      agents = AgentPlugin.where(status: 'active')
        .where('entity_id = ? OR entity_id IS NULL', entity.id)

      analyses = agents.map { |agent| analyze_agent(agent) }

      {
        timestamp: Time.current,
        agents_analyzed: analyses.count,
        top_performers: analyses.sort_by { |a| -(a[:performance][:success_rate] || 0) }.first(5),
        needs_improvement: analyses.select { |a| (a[:performance][:success_rate] || 100) < 70 },
        evolution_candidates: analyses.select { |a| a[:evolution_opportunities].any? },
        system_recommendations: generate_system_recommendations(analyses)
      }
    end

    # Trigger evolution for an agent (creates training task in Agent School)
    def evolve_agent(agent, focus_areas: [])
      analysis = analyze_agent(agent)
      
      return { success: false, reason: 'No evolution needed' } if analysis[:evolution_score] > 90

      training_plan = create_training_plan(agent, analysis, focus_areas)
      
      # Queue training in Agent School if available
      if agent_school_available?
        queue_agent_training(agent, training_plan)
        { success: true, status: 'training_queued', plan: training_plan }
      else
        { success: true, status: 'plan_created', plan: training_plan, note: 'Agent School not available - manual training required' }
      end
    end

    # Apply learned improvements to an agent
    def apply_evolution(agent, improvements:)
      applied = []

      improvements.each do |improvement|
        case improvement[:type]
        when 'add_tool'
          result = add_tool_to_agent(agent, improvement[:tool_name])
          applied << result
        when 'update_prompt'
          result = update_agent_prompt(agent, improvement[:prompt_addition])
          applied << result
        when 'add_capability'
          result = add_capability_to_agent(agent, improvement[:capability])
          applied << result
        when 'upgrade_model'
          result = upgrade_agent_model(agent, improvement[:model])
          applied << result
        end
      end

      # Increment version
      current_version = agent.version || '1.0.0'
      parts = current_version.split('.').map(&:to_i)
      parts[2] = (parts[2] || 0) + 1
      new_version = parts.join('.')
      
      agent.update!(version: new_version)

      {
        success: applied.all? { |r| r[:success] },
        applied: applied,
        new_version: new_version,
        message: "Applied #{applied.count { |r| r[:success] }}/#{improvements.count} improvements"
      }
    end

    private

    def calculate_performance_metrics(proposals)
      return {} if proposals.empty?

      completed = proposals.where(status: 'completed')
      failed = proposals.where(status: 'failed')
      rejected = proposals.where(status: 'rejected')

      {
        total_proposals: proposals.count,
        completed: completed.count,
        failed: failed.count,
        rejected: rejected.count,
        acceptance_rate: proposals.count > 0 ? (proposals.where(accepted: true).count.to_f / proposals.count * 100).round(1) : 0,
        success_rate: (completed.count + failed.count) > 0 ? (completed.count.to_f / (completed.count + failed.count) * 100).round(1) : 100,
        avg_confidence: proposals.where.not(confidence: nil).average(:confidence)&.round(2) || 0,
        avg_duration_ms: proposals.where.not(outcome_metrics: nil)
          .pluck(:outcome_metrics)
          .compact
          .map { |m| m['duration_ms'] }
          .compact
          .then { |durations| durations.any? ? (durations.sum / durations.count).round : nil }
      }
    end

    def identify_skill_gaps(proposals, agent)
      gaps = []

      # Analyze rejected proposals for missing tools
      rejected = proposals.where(status: 'rejected')
      missing_tools = rejected.pluck(:missing_tools).flatten.compact.tally

      missing_tools.each do |tool, count|
        gaps << {
          type: 'missing_tool',
          item: tool,
          frequency: count,
          impact: count >= 5 ? 'high' : (count >= 2 ? 'medium' : 'low'),
          recommendation: "Add tool '#{tool}' to agent's toolset"
        }
      end

      # Analyze failed proposals for capability gaps
      failed = proposals.where(status: 'failed')
      failure_reasons = failed.pluck(:failure_reason).compact

      # Pattern matching for common issues
      if failure_reasons.any? { |r| r.include?('not found') || r.include?('unknown') }
        gaps << {
          type: 'knowledge_gap',
          item: 'object_type_awareness',
          frequency: failure_reasons.count { |r| r.include?('not found') },
          impact: 'high',
          recommendation: 'Improve agent understanding of available object types'
        }
      end

      if failure_reasons.any? { |r| r.include?('validation') || r.include?('invalid') }
        gaps << {
          type: 'skill_gap',
          item: 'data_validation',
          frequency: failure_reasons.count { |r| r.include?('validation') },
          impact: 'medium',
          recommendation: 'Add data validation capabilities'
        }
      end

      gaps.sort_by { |g| g[:impact] == 'high' ? 0 : (g[:impact] == 'medium' ? 1 : 2) }
    end

    def find_evolution_opportunities(proposals, agent)
      opportunities = []

      metrics = calculate_performance_metrics(proposals)

      # Low success rate opportunity
      if metrics[:success_rate] && metrics[:success_rate] < 80
        opportunities << {
          type: 'improve_success_rate',
          current: metrics[:success_rate],
          target: 90,
          actions: ['review_failed_cases', 'update_prompt', 'add_tools']
        }
      end

      # Low acceptance rate opportunity
      if metrics[:acceptance_rate] && metrics[:acceptance_rate] < 70
        opportunities << {
          type: 'improve_acceptance_rate',
          current: metrics[:acceptance_rate],
          target: 85,
          actions: ['expand_capabilities', 'add_tools']
        }
      end

      # Slow performance opportunity
      if metrics[:avg_duration_ms] && metrics[:avg_duration_ms] > 30000
        opportunities << {
          type: 'improve_speed',
          current: metrics[:avg_duration_ms],
          target: 15000,
          actions: ['optimize_prompts', 'reduce_tool_calls']
        }
      end

      # Skill gap opportunities
      gaps = identify_skill_gaps(proposals, agent)
      high_impact_gaps = gaps.select { |g| g[:impact] == 'high' }
      
      if high_impact_gaps.any?
        opportunities << {
          type: 'address_skill_gaps',
          gaps: high_impact_gaps,
          actions: high_impact_gaps.map { |g| g[:recommendation] }
        }
      end

      opportunities
    end

    def generate_training_recommendations(proposals, agent)
      recommendations = []
      gaps = identify_skill_gaps(proposals, agent)

      # Tool training
      missing_tools = gaps.select { |g| g[:type] == 'missing_tool' }
      if missing_tools.any?
        recommendations << {
          type: 'tool_training',
          priority: 'high',
          focus: missing_tools.map { |g| g[:item] },
          description: 'Train agent on new tools to expand capabilities'
        }
      end

      # Prompt improvement
      failed = proposals.where(status: 'failed')
      if failed.count >= 3
        recommendations << {
          type: 'prompt_optimization',
          priority: 'medium',
          focus: ['error_handling', 'task_understanding'],
          description: 'Refine system prompt based on failure patterns'
        }
      end

      # Knowledge expansion
      if gaps.any? { |g| g[:type] == 'knowledge_gap' }
        recommendations << {
          type: 'knowledge_expansion',
          priority: 'medium',
          focus: ['platform_knowledge', 'object_types'],
          description: 'Expand agent knowledge of platform capabilities'
        }
      end

      recommendations
    end

    def calculate_evolution_score(proposals, agent)
      return 100 if proposals.empty? # New agents start at 100

      metrics = calculate_performance_metrics(proposals)
      gaps = identify_skill_gaps(proposals, agent)

      # Start at 100, subtract for issues
      score = 100

      # Subtract for low success rate
      if metrics[:success_rate]
        score -= (100 - metrics[:success_rate]) * 0.3
      end

      # Subtract for low acceptance rate
      if metrics[:acceptance_rate]
        score -= (100 - metrics[:acceptance_rate]) * 0.2
      end

      # Subtract for skill gaps
      gap_penalty = gaps.sum do |g|
        case g[:impact]
        when 'high' then 5
        when 'medium' then 2
        else 1
        end
      end
      score -= gap_penalty

      [score.round, 0].max
    end

    def create_training_plan(agent, analysis, focus_areas)
      {
        agent_slug: agent.slug,
        current_version: agent.version,
        evolution_score: analysis[:evolution_score],
        focus_areas: focus_areas.presence || default_focus_areas(analysis),
        training_tasks: build_training_tasks(agent, analysis),
        estimated_improvement: estimate_improvement(analysis),
        created_at: Time.current
      }
    end

    def default_focus_areas(analysis)
      areas = []
      
      if analysis[:skill_gaps].any?
        areas << 'skill_gaps'
      end
      
      if analysis[:performance][:success_rate].to_f < 80
        areas << 'success_rate'
      end

      areas.presence || ['general_improvement']
    end

    def build_training_tasks(agent, analysis)
      tasks = []

      analysis[:skill_gaps].each do |gap|
        tasks << {
          type: gap[:type],
          focus: gap[:item],
          action: gap[:recommendation],
          priority: gap[:impact]
        }
      end

      analysis[:recommended_training].each do |rec|
        tasks << {
          type: rec[:type],
          focus: rec[:focus],
          action: rec[:description],
          priority: rec[:priority]
        }
      end

      tasks.sort_by { |t| t[:priority] == 'high' ? 0 : (t[:priority] == 'medium' ? 1 : 2) }
    end

    def estimate_improvement(analysis)
      current = analysis[:evolution_score]
      gap_count = analysis[:skill_gaps].count
      
      # Estimate potential improvement
      potential_gain = [gap_count * 5, 30].min # Max 30 points improvement
      
      {
        current_score: current,
        estimated_score: [current + potential_gain, 100].min,
        confidence: gap_count > 5 ? 'low' : (gap_count > 2 ? 'medium' : 'high')
      }
    end

    def agent_school_available?
      # Check if Agent School system is set up
      defined?(AgentSchool) || AgentPlugin.exists?(slug: 'agent_school', status: 'active')
    end

    def queue_agent_training(agent, training_plan)
      # TODO: Integrate with Agent School system
      # For now, create a scheduled task for training
      Rails.logger.info "[AgentEvolution] Queued training for #{agent.slug}: #{training_plan[:training_tasks].count} tasks"
    end

    def add_tool_to_agent(agent, tool_name)
      existing = agent.agent_tools.find_by(tool_name: tool_name)
      return { success: true, tool: tool_name, status: 'already_exists' } if existing

      AgentTool.create!(agent_plugin: agent, tool_name: tool_name)
      { success: true, tool: tool_name, status: 'added' }
    rescue => e
      { success: false, tool: tool_name, error: e.message }
    end

    def update_agent_prompt(agent, prompt_addition)
      current_prompt = agent.system_prompt&.dig('prompt') || ''
      updated_prompt = "#{current_prompt}\n\n#{prompt_addition}"
      
      agent.update!(system_prompt: (agent.system_prompt || {}).merge('prompt' => updated_prompt))
      { success: true, status: 'prompt_updated' }
    rescue => e
      { success: false, error: e.message }
    end

    def add_capability_to_agent(agent, capability)
      current = agent.capabilities_definition&.dig('capabilities') || []
      return { success: true, status: 'already_exists' } if current.include?(capability)

      updated = current + [capability]
      agent.update!(
        capabilities_definition: (agent.capabilities_definition || {}).merge('capabilities' => updated)
      )
      { success: true, capability: capability, status: 'added' }
    rescue => e
      { success: false, error: e.message }
    end

    def upgrade_agent_model(agent, new_model)
      agent.update!(configuration: (agent.configuration || {}).merge('model' => new_model))
      { success: true, model: new_model, status: 'upgraded' }
    rescue => e
      { success: false, error: e.message }
    end

    def generate_system_recommendations(analyses)
      recommendations = []

      # Find agents that need improvement
      struggling = analyses.select { |a| (a[:performance][:success_rate] || 100) < 70 }
      if struggling.any?
        recommendations << {
          type: 'training',
          priority: 'high',
          agents: struggling.map { |a| a[:agent][:slug] },
          action: 'Schedule training for struggling agents',
          impact: 'Could improve overall system success rate by 10-20%'
        }
      end

      # Find common skill gaps across agents
      all_gaps = analyses.flat_map { |a| a[:skill_gaps] }
      common_missing_tools = all_gaps
        .select { |g| g[:type] == 'missing_tool' }
        .map { |g| g[:item] }
        .tally
        .select { |_, count| count >= 2 }
        .keys

      if common_missing_tools.any?
        recommendations << {
          type: 'tool_creation',
          priority: 'high',
          tools: common_missing_tools,
          action: 'Create commonly needed tools',
          impact: 'Would enable multiple agents to handle more task types'
        }
      end

      # Check for overloaded agents
      high_volume_agents = analyses.select { |a| (a[:performance][:total_proposals] || 0) > 50 }
      if high_volume_agents.any?
        recommendations << {
          type: 'load_balancing',
          priority: 'medium',
          agents: high_volume_agents.map { |a| a[:agent][:slug] },
          action: 'Consider creating specialized agents to distribute workload',
          impact: 'Improved response times and reduced failure rates'
        }
      end

      # Check for underutilized agents
      low_volume = analyses.select { |a| (a[:performance][:total_proposals] || 0) < 5 }
      if low_volume.count > analyses.count / 2
        recommendations << {
          type: 'agent_consolidation',
          priority: 'low',
          agents: low_volume.map { |a| a[:agent][:slug] },
          action: 'Review underutilized agents for potential consolidation',
          impact: 'Simplified agent ecosystem, easier maintenance'
        }
      end

      recommendations.sort_by { |r| r[:priority] == 'high' ? 0 : (r[:priority] == 'medium' ? 1 : 2) }
    end
  end
end

