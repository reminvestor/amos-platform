# frozen_string_literal: true

module LivingPlatform
  # DesireEngine - Autonomous Goal Generation
  #
  # The Desire Engine gives the platform "drives" - it analyzes the current state
  # and generates goals that the platform should pursue on its own, without
  # human intervention.
  #
  # Goal Types:
  # - improvement: Make underperforming agents/tools better
  # - expansion: Build new capabilities to address unmet needs
  # - maintenance: Fix, clean, or optimize components
  # - learning: Research and acquire new knowledge
  # - social: Help agents collaborate better
  #
  # Integration:
  # - Uses EvolutionService for agent analysis
  # - Triggers AgentSchool for training goals
  # - Creates AgentGoal records for tracking
  # - Schedules ScheduledAgentTask for execution
  #
  class DesireEngine
    attr_reader :entity

    # Configuration
    MAX_GOALS_PER_CYCLE = 10
    MIN_PRIORITY_TO_EXECUTE = 50
    IMPROVEMENT_THRESHOLD = 0.7  # Agents below this success rate need help

    def initialize(entity)
      @entity = entity
      @evolution_service = Agents::EvolutionService.new(entity: entity)
    end

    # Main entry point - generate all goals for this entity
    def generate_daily_goals
      Rails.logger.info "[DesireEngine] Generating daily goals for entity #{entity.id}"
      
      goals = []
      
      # 1. IMPROVEMENT DESIRES - Based on performance metrics
      goals.concat(generate_improvement_goals)
      
      # 2. EXPANSION DESIRES - Based on unmet needs
      goals.concat(generate_expansion_goals)
      
      # 3. MAINTENANCE DESIRES - Based on system health
      goals.concat(generate_maintenance_goals)
      
      # 4. LEARNING DESIRES - Based on knowledge gaps
      goals.concat(generate_learning_goals)
      
      # 5. SOCIAL DESIRES - Based on collaboration patterns
      goals.concat(generate_social_goals)
      
      # Prioritize and limit
      prioritized_goals = prioritize_goals(goals).first(MAX_GOALS_PER_CYCLE)
      
      # Create goal records
      created_goals = prioritized_goals.map do |goal_spec|
        create_goal(goal_spec)
      end.compact
      
      Rails.logger.info "[DesireEngine] Generated #{created_goals.count} goals"
      
      {
        goals_generated: created_goals.count,
        goals: created_goals,
        breakdown: {
          improvement: created_goals.count { |g| g.goal_type == 'improvement' },
          expansion: created_goals.count { |g| g.goal_type == 'expansion' },
          maintenance: created_goals.count { |g| g.goal_type == 'maintenance' },
          learning: created_goals.count { |g| g.goal_type == 'learning' },
          social: created_goals.count { |g| g.goal_type == 'social' }
        }
      }
    end

    # Schedule goals for execution
    def schedule_pending_goals
      pending_goals = AgentGoal.where(entity: entity, status: 'pending')
        .where('priority >= ?', MIN_PRIORITY_TO_EXECUTE)
        .by_priority
        .limit(5)
      
      scheduled = pending_goals.map do |goal|
        schedule_goal(goal)
      end.compact
      
      Rails.logger.info "[DesireEngine] Scheduled #{scheduled.count} goals for execution"
      scheduled
    end

    private

    # ═══════════════════════════════════════════════════════════════════════════
    # IMPROVEMENT GOALS
    # Find underperforming agents and create goals to improve them
    # ═══════════════════════════════════════════════════════════════════════════

    def generate_improvement_goals
      goals = []
      
      # Get agent analyses
      entity.agent_plugins.where(status: 'active').find_each do |agent|
        analysis = @evolution_service.analyze_agent(agent)
        success_rate = analysis.dig(:performance, :success_rate) || 100
        
        next if success_rate >= IMPROVEMENT_THRESHOLD * 100
        
        # This agent needs improvement
        goals << {
          goal_type: 'improvement',
          title: "Improve #{agent.name} success rate",
          description: "#{agent.name} has a success rate of #{success_rate.round(1)}%, " \
                       "which is below the target of #{(IMPROVEMENT_THRESHOLD * 100).round}%.",
          priority: calculate_improvement_priority(analysis),
          target: agent,
          success_criteria: {
            'success_rate' => { 'min' => IMPROVEMENT_THRESHOLD * 100 }
          },
          current_metrics: {
            'success_rate' => success_rate,
            'total_tasks' => analysis.dig(:performance, :total_proposals) || 0
          },
          target_metrics: {
            'success_rate' => IMPROVEMENT_THRESHOLD * 100
          },
          suggested_actions: analysis[:recommended_training].map { |t| t[:type] },
          metadata: {
            skill_gaps: analysis[:skill_gaps],
            evolution_score: analysis[:evolution_score]
          }
        }
      end
      
      goals
    end

    def calculate_improvement_priority(analysis)
      base_priority = 50
      
      # Lower success rate = higher priority
      success_rate = analysis.dig(:performance, :success_rate) || 100
      base_priority += (100 - success_rate) * 0.3
      
      # More executions = higher priority (agent is actually used)
      total = analysis.dig(:performance, :total_proposals) || 0
      base_priority += [total / 10, 20].min
      
      # High impact skill gaps = higher priority
      high_gaps = (analysis[:skill_gaps] || []).count { |g| g[:impact] == 'high' }
      base_priority += high_gaps * 5
      
      [[base_priority.round, 100].min, 1].max
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # EXPANSION GOALS
    # Find unmet needs and create goals to build new capabilities
    # ═══════════════════════════════════════════════════════════════════════════

    def generate_expansion_goals
      goals = []
      
      # Analyze rejected/failed proposals for patterns
      unmet_needs = detect_unmet_needs
      
      unmet_needs.each do |need|
        goals << {
          goal_type: 'expansion',
          title: "Build capability: #{need[:description].truncate(50)}",
          description: "Users have requested this #{need[:request_count]} times " \
                       "but no agent could handle it: #{need[:description]}",
          priority: calculate_expansion_priority(need),
          target: nil,  # Entity-wide
          success_criteria: {
            'capability_exists' => { 'equals' => true }
          },
          current_metrics: {
            'request_count' => need[:request_count],
            'failure_count' => need[:failure_count]
          },
          target_metrics: {
            'capability_exists' => true
          },
          suggested_actions: need[:suggested_actions] || ['create_agent', 'create_tool'],
          metadata: {
            sample_requests: need[:sample_requests],
            missing_tools: need[:missing_tools]
          }
        }
      end
      
      goals
    end

    def detect_unmet_needs
      # Analyze rejected proposals to find patterns
      rejected_proposals = AgentTaskProposal.where(entity: entity, status: 'rejected')
        .where('created_at > ?', 30.days.ago)
      
      # Group by similar task descriptions
      needs = rejected_proposals.group_by do |p|
        # Simplify task description to find patterns
        simplify_task_description(p.task_description)
      end
      
      needs.map do |pattern, proposals|
        next if proposals.count < 3  # Need at least 3 occurrences
        
        {
          description: pattern,
          request_count: proposals.count,
          failure_count: proposals.count { |p| p.status == 'failed' },
          sample_requests: proposals.first(3).map(&:task_description),
          missing_tools: proposals.flat_map { |p| p.missing_tools || [] }.uniq.first(5),
          suggested_actions: suggest_expansion_actions(proposals)
        }
      end.compact
    end

    def simplify_task_description(description)
      return '' if description.blank?
      
      # Remove specific details, keep the action type
      description.downcase
        .gsub(/\b(the|a|an|my|your|this|that)\b/, '')
        .gsub(/\d+/, 'N')
        .gsub(/["'].*?["']/, 'X')
        .gsub(/\s+/, ' ')
        .strip
        .truncate(100)
    end

    def suggest_expansion_actions(proposals)
      actions = []
      
      # If missing tools, suggest creating them
      missing = proposals.flat_map { |p| p.missing_tools || [] }.uniq
      actions << 'create_tool' if missing.any?
      
      # If no agent could handle, suggest new agent
      if proposals.all? { |p| p.rejection_reason&.include?('No suitable agent') }
        actions << 'create_agent'
      end
      
      actions.presence || ['create_agent', 'create_tool']
    end

    def calculate_expansion_priority(need)
      base_priority = 40
      
      # More requests = higher priority
      base_priority += [need[:request_count] * 2, 30].min
      
      # More failures = higher priority
      base_priority += [need[:failure_count] * 3, 20].min
      
      [[base_priority.round, 100].min, 1].max
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # MAINTENANCE GOALS
    # Find unhealthy components and create goals to fix them
    # ═══════════════════════════════════════════════════════════════════════════

    def generate_maintenance_goals
      goals = []
      
      # Check for unresolved anomalies
      unresolved_anomalies = PlatformAnomaly.where(entity: entity)
        .active
        .where(triggered_goal_id: nil)
      
      unresolved_anomalies.find_each do |anomaly|
        goals << {
          goal_type: 'maintenance',
          title: "Resolve: #{anomaly.title}",
          description: "Anomaly detected: #{anomaly.description}",
          priority: anomaly_to_priority(anomaly.severity),
          target: anomaly.target,
          success_criteria: {
            'anomaly_resolved' => { 'equals' => true }
          },
          current_metrics: anomaly.triggering_metrics,
          target_metrics: { 'anomaly_resolved' => true },
          suggested_actions: anomaly.suggested_actions,
          metadata: { anomaly_id: anomaly.id, severity: anomaly.severity }
        }
      end
      
      # Check for stale agents (no activity in 30 days)
      stale_agents = find_stale_agents
      stale_agents.each do |agent|
        goals << {
          goal_type: 'maintenance',
          title: "Review stale agent: #{agent.name}",
          description: "Agent #{agent.name} has had no activity in 30+ days. " \
                       "Consider retirement or reassignment.",
          priority: 30,
          target: agent,
          success_criteria: {
            'agent_reviewed' => { 'equals' => true }
          },
          current_metrics: {
            'days_inactive' => days_since_last_activity(agent)
          },
          target_metrics: { 'agent_reviewed' => true },
          suggested_actions: ['evaluate_for_retirement', 'reassign_tasks', 'reactivate'],
          metadata: { last_activity: agent.agent_plugin_executions.maximum(:created_at) }
        }
      end
      
      goals
    end

    def find_stale_agents
      entity.agent_plugins
        .where(status: 'active')
        .where.not(id: AgentPluginExecution
          .where('created_at > ?', 30.days.ago)
          .select(:agent_plugin_id))
    end

    def days_since_last_activity(agent)
      last_exec = agent.agent_plugin_executions.maximum(:created_at)
      return 999 unless last_exec
      ((Time.current - last_exec) / 1.day).round
    end

    def anomaly_to_priority(severity)
      case severity
      when 'critical' then 95
      when 'high' then 80
      when 'medium' then 60
      when 'low' then 40
      else 50
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # LEARNING GOALS
    # Find knowledge gaps and create goals to address them
    # ═══════════════════════════════════════════════════════════════════════════

    def generate_learning_goals
      goals = []
      
      # Analyze agent reflections for knowledge gaps
      recent_reflections = AgentReflection.where(entity: entity)
        .where('created_at > ?', 7.days.ago)
        .where("jsonb_array_length(knowledge_gaps) > 0")
      
      knowledge_gaps = recent_reflections.flat_map { |r| r.knowledge_gaps }
        .group_by { |g| g['topic'] || g[:topic] }
        .transform_values(&:count)
        .sort_by { |_, count| -count }
        .first(5)
      
      knowledge_gaps.each do |topic, count|
        next if count < 2  # Need multiple agents to identify the same gap
        
        goals << {
          goal_type: 'learning',
          title: "Research: #{topic.to_s.truncate(50)}",
          description: "#{count} agents identified a knowledge gap in: #{topic}",
          priority: 40 + [count * 5, 30].min,
          target: nil,  # Entity-wide
          success_criteria: {
            'knowledge_acquired' => { 'equals' => true }
          },
          current_metrics: { 'gap_count' => count },
          target_metrics: { 'knowledge_acquired' => true },
          suggested_actions: ['research_topic', 'add_to_knowledge_base', 'update_prompts'],
          metadata: { topic: topic, reporting_agents: count }
        }
      end
      
      goals
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # SOCIAL GOALS
    # Improve agent collaboration and relationships
    # ═══════════════════════════════════════════════════════════════════════════

    def generate_social_goals
      goals = []
      
      # Find agents with low collaboration success
      weak_collaborators = find_weak_collaborators
      weak_collaborators.each do |agent, stats|
        goals << {
          goal_type: 'social',
          title: "Improve collaboration: #{agent.name}",
          description: "#{agent.name} has a collaboration success rate of #{stats[:success_rate].round(1)}%",
          priority: 35 + [(100 - stats[:success_rate]) * 0.3, 30].min.round,
          target: agent,
          success_criteria: {
            'collaboration_success_rate' => { 'min' => 70 }
          },
          current_metrics: stats,
          target_metrics: { 'collaboration_success_rate' => 70 },
          suggested_actions: ['assign_mentor', 'improve_handoff_prompts', 'training'],
          metadata: { weak_relationships: stats[:weak_relationships] }
        }
      end
      
      # Find isolated agents (no collaborations)
      isolated_agents = find_isolated_agents
      isolated_agents.each do |agent|
        goals << {
          goal_type: 'social',
          title: "Integrate agent: #{agent.name}",
          description: "#{agent.name} has never collaborated with other agents",
          priority: 25,
          target: agent,
          success_criteria: {
            'has_collaborations' => { 'equals' => true }
          },
          current_metrics: { 'collaboration_count' => 0 },
          target_metrics: { 'has_collaborations' => true },
          suggested_actions: ['introduce_to_team', 'assign_collaborative_task'],
          metadata: {}
        }
      end
      
      goals
    end

    def find_weak_collaborators
      # Get agents with collaboration relationships
      agent_stats = {}
      
      AgentRelationship.where(entity: entity).find_each do |rel|
        [rel.requester, rel.helper].each do |agent|
          agent_stats[agent] ||= { total: 0, successful: 0, weak_relationships: [] }
          agent_stats[agent][:total] += rel.total_collaborations
          agent_stats[agent][:successful] += rel.successful_collaborations
          
          if rel.success_rate < 0.5 && rel.total_collaborations >= 3
            agent_stats[agent][:weak_relationships] << rel.id
          end
        end
      end
      
      agent_stats.transform_values! do |stats|
        stats[:success_rate] = stats[:total] > 0 ? (stats[:successful].to_f / stats[:total] * 100) : 100
        stats
      end
      
      # Return agents with < 60% collaboration success rate
      agent_stats.select { |_, stats| stats[:success_rate] < 60 && stats[:total] >= 5 }
    end

    def find_isolated_agents
      # Agents that have never collaborated
      collaborated_ids = AgentRelationship.where(entity: entity)
        .pluck(:requester_id, :helper_id)
        .flatten
        .uniq
      
      entity.agent_plugins.where(status: 'active')
        .where.not(id: collaborated_ids)
        .where('created_at < ?', 7.days.ago)  # Give new agents time
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # GOAL MANAGEMENT
    # ═══════════════════════════════════════════════════════════════════════════

    def prioritize_goals(goals)
      goals.sort_by { |g| -g[:priority] }
    end

    def create_goal(goal_spec)
      # Check if similar goal already exists
      existing = AgentGoal.where(entity: entity)
        .active
        .where(goal_type: goal_spec[:goal_type])
        .where(target_type: goal_spec[:target]&.class&.name)
        .where(target_id: goal_spec[:target]&.id)
        .first
      
      return nil if existing
      
      AgentGoal.create!(
        entity: entity,
        agent_plugin: goal_spec[:target].is_a?(AgentPlugin) ? goal_spec[:target] : nil,
        goal_type: goal_spec[:goal_type],
        title: goal_spec[:title],
        description: goal_spec[:description],
        priority: goal_spec[:priority],
        status: 'pending',
        target_type: goal_spec[:target]&.class&.name,
        target_id: goal_spec[:target]&.id,
        success_criteria: goal_spec[:success_criteria],
        current_metrics: goal_spec[:current_metrics],
        target_metrics: goal_spec[:target_metrics],
        suggested_actions: goal_spec[:suggested_actions],
        source: 'desire_engine',
        metadata: goal_spec[:metadata] || {}
      )
    rescue => e
      Rails.logger.error "[DesireEngine] Failed to create goal: #{e.message}"
      nil
    end

    def schedule_goal(goal)
      # Find the best executor for this goal
      executor = find_executor_for_goal(goal)
      return nil unless executor
      
      # Create execution task
      goal.create_execution_task!(
        executor_agent: executor,
        prompt: build_goal_prompt(goal)
      )
      
      goal
    rescue => e
      Rails.logger.error "[DesireEngine] Failed to schedule goal #{goal.id}: #{e.message}"
      nil
    end

    def find_executor_for_goal(goal)
      case goal.goal_type
      when 'improvement'
        # Use the planner or the target agent itself
        goal.target || find_planner_agent
      when 'expansion'
        # Use platform factory if available
        find_platform_factory_agent || find_planner_agent
      when 'maintenance'
        # Use the target agent or a maintenance specialist
        goal.target.is_a?(AgentPlugin) ? goal.target : find_planner_agent
      when 'learning'
        # Use a research agent
        find_research_agent || find_planner_agent
      when 'social'
        # Use the target agent
        goal.target.is_a?(AgentPlugin) ? goal.target : find_planner_agent
      else
        find_planner_agent
      end
    end

    def find_planner_agent
      entity.agent_plugins.find_by(slug: 'planner', status: 'active') ||
        entity.agent_plugins.where(status: 'active').first
    end

    def find_platform_factory_agent
      entity.agent_plugins.find_by(slug: 'platform_factory', status: 'active')
    end

    def find_research_agent
      entity.agent_plugins.find_by(slug: 'research_agent', status: 'active') ||
        entity.agent_plugins.where(status: 'active')
          .where("system_prompt->>'prompt' ILIKE '%research%'")
          .first
    end

    def build_goal_prompt(goal)
      <<~PROMPT
        You are executing an autonomous goal generated by the Desire Engine.
        
        Goal Type: #{goal.goal_type.upcase}
        Title: #{goal.title}
        Description: #{goal.description}
        
        Current Metrics:
        #{JSON.pretty_generate(goal.current_metrics)}
        
        Target Metrics:
        #{JSON.pretty_generate(goal.target_metrics)}
        
        Success Criteria:
        #{JSON.pretty_generate(goal.success_criteria)}
        
        Suggested Actions:
        #{goal.suggested_actions.join("\n- ")}
        
        Additional Context:
        #{JSON.pretty_generate(goal.metadata)}
        
        Instructions:
        1. Analyze the current state
        2. Execute the suggested actions or determine better alternatives
        3. Measure progress toward the target metrics
        4. Report your results including what you accomplished and what remains
        
        Be thorough but efficient. Focus on achieving the success criteria.
      PROMPT
    end
  end
end


