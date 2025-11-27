# frozen_string_literal: true

module Collaboration
  class IreplaceabilityAwareRouter
    def initialize(entity:)
      @entity = entity
    end

    # ============================================
    # MAIN ROUTING
    # ============================================

    def route_task(task)
      # Get all agents that could handle this task
      capable_agents = find_capable_agents(task)

      if capable_agents.empty?
        return { error: 'No capable agents available', agent: nil }
      end

      # Score each agent
      scored_agents = capable_agents.map do |agent|
        score_agent(agent, task, capable_agents)
      end

      # Sort by final score
      scored_agents.sort_by! { |sa| -sa[:final_score] }

      # Select best agent with special handling for probation
      select_best_agent(scored_agents)
    end

    # ============================================
    # AGENT DISCOVERY
    # ============================================

    def find_capable_agents(task)
      task_description = extract_task_description(task)
      task_type = classify_task_type(task_description)

      # Start with available agents
      agents = AgentPlugin.available.where(entity: @entity)

      # Filter by capability if we can determine task type
      if task_type != 'general'
        # Prefer agents with relevant capabilities
        with_capability = agents.joins(:capability_beliefs)
          .where(agent_capability_beliefs: { task_type: task_type })
          .where('agent_capability_beliefs.avg_quality > ?', 0.4)

        agents = with_capability if with_capability.exists?
      end

      agents.includes(:energy_state, :capability_beliefs)
    end

    private

    # ============================================
    # SCORING
    # ============================================

    def score_agent(agent, task, all_capable)
      base_score = calculate_base_score(agent, task)
      status_modifier = status_score_modifier(agent)
      irreplaceability_bonus = irreplaceability_bonus(agent, task, all_capable)

      {
        agent: agent,
        base_score: base_score,
        status_modifier: status_modifier,
        irreplaceability_bonus: irreplaceability_bonus,
        final_score: (base_score * status_modifier) + irreplaceability_bonus,
        is_only_option: all_capable.size == 1,
        is_probation: agent.on_probation?
      }
    end

    def calculate_base_score(agent, task)
      task_type = classify_task_type(extract_task_description(task))

      # Capability match
      belief = agent.capability_beliefs.find_by(task_type: task_type)
      capability_match = belief&.avg_quality || 0.5

      # Historical success
      historical_success = agent.success_rate_for_task_type(task)

      # Current energy (normalized)
      energy_factor = (agent.current_energy / 100.0).clamp(0, 1)

      # Availability
      availability = agent.availability_score

      # Weighted combination
      (capability_match * 0.35) +
        (historical_success * 0.30) +
        (energy_factor * 0.20) +
        (availability * 0.15)
    end

    def status_score_modifier(agent)
      case agent.status
      when 'active'
        1.0
      when 'probation'
        agent.priority_score || 0.5
      when 'testing'
        0.7  # Testing agents get some tasks but not priority
      else
        0.0  # Don't route to in_school, archived, etc.
      end
    end

    def irreplaceability_bonus(agent, task, all_capable)
      # Bonus for being the only agent that can do this
      if all_capable.size == 1
        return 0.5  # Significant bonus
      end

      # Check if this agent has unique capabilities for this task
      task_type = classify_task_type(extract_task_description(task))

      unique_for_task = all_capable.count do |other|
        other.id != agent.id &&
          other.capability_beliefs.exists?(task_type: task_type, is_specialty: true)
      end.zero?

      if unique_for_task && agent.capability_beliefs.exists?(task_type: task_type, is_specialty: true)
        0.3  # Unique specialist bonus
      else
        0.0
      end
    end

    # ============================================
    # SELECTION
    # ============================================

    def select_best_agent(scored_agents)
      best = scored_agents.first

      # If best is on probation but is the ONLY option, use them
      if best[:is_probation] && best[:is_only_option]
        Rails.logger.warn "[Router] Using probationary agent #{best[:agent].name} - only capable agent"
        return {
          agent: best[:agent],
          reason: :only_capable_agent,
          score: best[:final_score],
          warning: 'Using probationary agent as only option'
        }
      end

      # If best is on probation but others exist, consider alternatives
      if best[:is_probation]
        active_alternative = scored_agents.find { |sa| !sa[:is_probation] && sa[:status_modifier] == 1.0 }

        if active_alternative && active_alternative[:final_score] > best[:final_score] * 0.7
          # Active agent is close enough in score - prefer them
          return {
            agent: active_alternative[:agent],
            reason: :prefer_active_over_probation,
            score: active_alternative[:final_score],
            passed_over: best[:agent].name
          }
        end
      end

      {
        agent: best[:agent],
        reason: :best_score,
        score: best[:final_score]
      }
    end

    # ============================================
    # HELPERS
    # ============================================

    def extract_task_description(task)
      case task
      when String
        task
      when Hash
        task[:description] || task['description'] || task[:task_description] || task['task_description'] || ''
      else
        task.respond_to?(:description) ? task.description : ''
      end.to_s
    end

    def classify_task_type(description)
      desc = description.downcase

      if desc.include?('analyze') || desc.include?('analysis')
        'analysis'
      elsif desc.include?('create') || desc.include?('generate') || desc.include?('build')
        'creation'
      elsif desc.include?('research') || desc.include?('find') || desc.include?('search')
        'research'
      elsif desc.include?('integrate') || desc.include?('api') || desc.include?('connect')
        'integration'
      elsif desc.include?('email') || desc.include?('message') || desc.include?('send')
        'communication'
      elsif desc.include?('report') || desc.include?('visualiz') || desc.include?('chart')
        'reporting'
      elsif desc.include?('fix') || desc.include?('debug') || desc.include?('error')
        'debugging'
      else
        'general'
      end
    end
  end
end

