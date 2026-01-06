# frozen_string_literal: true

module LivingPlatform
  # EvolutionCycleService - Continuous Self-Improvement Loop
  #
  # Orchestrates the complete evolution cycle:
  # 1. PERCEIVE: Gather metrics and detect anomalies
  # 2. ANALYZE: Identify what's working and what's not
  # 3. HYPOTHESIZE: Generate ideas for improvement
  # 4. EXPERIMENT: Run A/B tests on promising changes
  # 5. INTEGRATE: Promote successful experiments
  # 6. DOCUMENT: Record what was learned
  #
  # Integration:
  # - Uses PerceptionService for metrics
  # - Uses EvolutionService for agent analysis
  # - Uses AgentAbTest for experiments
  # - Uses DesireEngine for goal generation
  # - Creates EvolutionCycle records
  #
  class EvolutionCycleService
    attr_reader :entity, :cycle

    # Configuration
    MAX_EXPERIMENTS_PER_CYCLE = 3
    MIN_DATA_POINTS_FOR_EXPERIMENT = 20
    EXPERIMENT_TARGET_TASKS = 100

    def initialize(entity)
      @entity = entity
      @perception_service = PerceptionService.new(entity)
      @evolution_service = Agents::EvolutionService.new(entity: entity)
      @desire_engine = DesireEngine.new(entity)
    end

    # Run a complete evolution cycle
    def run_cycle(type: 'daily')
      Rails.logger.info "[EvolutionCycle] Starting #{type} cycle for entity #{entity.id}"
      
      @cycle = EvolutionCycle.create!(
        entity: entity,
        cycle_type: type,
        status: 'running',
        started_at: Time.current
      )
      
      begin
        # PHASE 1: PERCEPTION
        perception = run_perception_phase
        
        # PHASE 2: ANALYSIS
        analysis = run_analysis_phase(perception)
        
        # PHASE 3: HYPOTHESIS
        hypotheses = run_hypothesis_phase(analysis)
        
        # PHASE 4: EXPERIMENTATION
        experiments = run_experimentation_phase(hypotheses)
        
        # PHASE 5: INTEGRATION
        integrations = run_integration_phase
        
        # PHASE 6: DOCUMENTATION
        run_documentation_phase(analysis, integrations)
        
        # Generate goals for next cycle
        goals = @desire_engine.generate_daily_goals
        @cycle.update!(goals_generated: goals[:goals_generated])
        
        @cycle.complete!
        
        Rails.logger.info "[EvolutionCycle] Cycle #{@cycle.id} completed successfully"
        
        @cycle
      rescue => e
        Rails.logger.error "[EvolutionCycle] Cycle failed: #{e.message}"
        @cycle.fail!(e.message)
        raise
      end
    end

    # Check and promote completed experiments
    def check_experiments
      running_experiments = AgentAbTest.where(entity: entity, status: 'running')
      
      promotions = []
      
      running_experiments.each do |experiment|
        next unless experiment.completed?
        
        if experiment.variant_significantly_better?
          promotion = promote_experiment(experiment)
          promotions << promotion if promotion
        else
          experiment.update!(status: 'completed')
        end
      end
      
      promotions
    end

    private

    # ═══════════════════════════════════════════════════════════════════════════
    # PHASE 1: PERCEPTION
    # ═══════════════════════════════════════════════════════════════════════════

    def run_perception_phase
      Rails.logger.info "[EvolutionCycle] Phase 1: Perception"
      
      perception = @perception_service.perceive(type: 'routine')
      
      @cycle.record_perception(
        metrics: perception.metrics_snapshot,
        anomalies: perception.anomalies,
        opportunities: perception.opportunities,
        threats: perception.threats
      )
      
      perception
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PHASE 2: ANALYSIS
    # ═══════════════════════════════════════════════════════════════════════════

    def run_analysis_phase(perception)
      Rails.logger.info "[EvolutionCycle] Phase 2: Analysis"
      
      # Get comprehensive analysis from evolution service
      all_agents_analysis = @evolution_service.analyze_all_agents
      
      # Identify improvement candidates
      improvement_candidates = all_agents_analysis[:needs_improvement] || []
      evolution_candidates = all_agents_analysis[:evolution_candidates] || []
      
      analysis = {
        overall_health: perception.overall_health_score,
        agents_analyzed: all_agents_analysis[:agents_analyzed],
        improvement_candidates: improvement_candidates.map { |a| a[:agent][:slug] },
        evolution_candidates: evolution_candidates.map { |a| a[:agent][:slug] },
        system_recommendations: all_agents_analysis[:system_recommendations],
        anomaly_patterns: analyze_anomaly_patterns(perception.anomalies),
        timestamp: Time.current
      }
      
      @cycle.record_analysis(results: analysis, hypotheses: [])
      
      analysis
    end

    def analyze_anomaly_patterns(anomalies)
      return {} if anomalies.blank?
      
      patterns = {
        by_type: anomalies.group_by { |a| a['anomaly_type'] || a[:anomaly_type] }.transform_values(&:count),
        by_severity: anomalies.group_by { |a| a['severity'] || a[:severity] }.transform_values(&:count),
        total: anomalies.count
      }
      
      patterns
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PHASE 3: HYPOTHESIS
    # ═══════════════════════════════════════════════════════════════════════════

    def run_hypothesis_phase(analysis)
      Rails.logger.info "[EvolutionCycle] Phase 3: Hypothesis Generation"
      
      hypotheses = []
      
      # Hypothesis 1: Prompt improvements for struggling agents
      analysis[:improvement_candidates].each do |agent_slug|
        agent = entity.agent_plugins.find_by(slug: agent_slug)
        next unless agent
        
        agent_analysis = @evolution_service.analyze_agent(agent)
        
        hypotheses << {
          type: :prompt_improvement,
          agent: agent,
          current_prompt: agent.system_prompt&.dig('prompt'),
          hypothesis: "Improving the system prompt based on failure patterns will increase success rate",
          expected_improvement: estimate_prompt_improvement(agent_analysis),
          priority: agent_analysis[:evolution_score] < 50 ? 'high' : 'medium',
          data_points: agent_analysis.dig(:performance, :total_proposals) || 0
        }
      end
      
      # Hypothesis 2: Tool additions based on skill gaps
      system_recs = analysis[:system_recommendations] || []
      tool_rec = system_recs.find { |r| r[:type] == 'tool_creation' }
      
      if tool_rec
        hypotheses << {
          type: :new_tool,
          tools: tool_rec[:tools],
          hypothesis: "Creating commonly needed tools will reduce failure rates",
          expected_improvement: 15,
          priority: 'medium'
        }
      end
      
      # Hypothesis 3: Load balancing
      load_rec = system_recs.find { |r| r[:type] == 'load_balancing' }
      
      if load_rec
        hypotheses << {
          type: :load_balancing,
          agents: load_rec[:agents],
          hypothesis: "Distributing workload will improve response times and success rates",
          expected_improvement: 10,
          priority: 'low'
        }
      end
      
      # Filter and prioritize
      valid_hypotheses = hypotheses.select { |h| h[:data_points].to_i >= MIN_DATA_POINTS_FOR_EXPERIMENT || h[:type] != :prompt_improvement }
      sorted_hypotheses = valid_hypotheses.sort_by do |h|
        priority_score = case h[:priority]
                         when 'high' then 0
                         when 'medium' then 1
                         else 2
                         end
        [priority_score, -h[:expected_improvement].to_i]
      end
      
      @cycle.update!(improvement_hypotheses: sorted_hypotheses.map { |h| h.except(:agent, :current_prompt) })
      
      sorted_hypotheses
    end

    def estimate_prompt_improvement(agent_analysis)
      # Estimate potential improvement based on identified issues
      base = 5
      
      # More skill gaps = more room for improvement
      gaps = agent_analysis[:skill_gaps] || []
      base += gaps.count * 2
      
      # Lower current score = more room for improvement
      current_score = agent_analysis[:evolution_score] || 80
      base += (100 - current_score) / 10
      
      [base, 30].min  # Cap at 30% expected improvement
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PHASE 4: EXPERIMENTATION
    # ═══════════════════════════════════════════════════════════════════════════

    def run_experimentation_phase(hypotheses)
      Rails.logger.info "[EvolutionCycle] Phase 4: Experimentation"
      
      experiments = []
      
      # Take top hypotheses up to max
      hypotheses.first(MAX_EXPERIMENTS_PER_CYCLE).each do |hypothesis|
        experiment = create_experiment(hypothesis)
        experiments << experiment if experiment
      end
      
      @cycle.update!(experiments_started: experiments.count)
      
      experiments
    end

    def create_experiment(hypothesis)
      case hypothesis[:type]
      when :prompt_improvement
        create_prompt_experiment(hypothesis)
      when :new_tool
        # Tool creation is not an A/B test, it's a build task
        create_tool_creation_goal(hypothesis)
        nil
      when :load_balancing
        # Load balancing requires architecture changes, create goal
        create_load_balancing_goal(hypothesis)
        nil
      else
        nil
      end
    end

    def create_prompt_experiment(hypothesis)
      agent = hypothesis[:agent]
      current_prompt = hypothesis[:current_prompt] || ''
      
      # Generate improved prompt using AI
      improved_prompt = generate_improved_prompt(agent, current_prompt)
      
      return nil unless improved_prompt
      
      # Create A/B test
      experiment = AgentAbTest.create!(
        entity: entity,
        evolution_cycle: @cycle,
        control_agent: agent,
        variant_agent: agent,  # Same agent, different config for now
        target_tasks: EXPERIMENT_TARGET_TASKS,
        status: 'running',
        started_at: Time.current,
        metadata: {
          type: 'prompt_improvement',
          hypothesis: hypothesis[:hypothesis],
          control_prompt: current_prompt,
          variant_prompt: improved_prompt,
          expected_improvement: hypothesis[:expected_improvement]
        }
      )
      
      @cycle.start_experiment(experiment)
      
      Rails.logger.info "[EvolutionCycle] Created prompt experiment #{experiment.id} for #{agent.name}"
      
      experiment
    end

    def generate_improved_prompt(agent, current_prompt)
      # Get agent's recent failures
      failures = agent.agent_plugin_executions
        .where(status: 'failed')
        .where('created_at > ?', 7.days.ago)
        .limit(10)
      
      failure_patterns = failures.map do |f|
        {
          error: f.output_result&.dig('error'),
          task: f.input_context&.dig('task_description')&.truncate(100)
        }
      end
      
      prompt = <<~PROMPT
        You are an AI prompt engineer. Improve this agent's system prompt based on its failure patterns.
        
        Current prompt:
        ```
        #{current_prompt.truncate(2000)}
        ```
        
        Recent failure patterns:
        #{failure_patterns.map { |f| "- #{f[:task]}: #{f[:error]}" }.join("\n")}
        
        Generate an improved version of the system prompt that:
        1. Addresses the failure patterns
        2. Adds better error handling guidance
        3. Clarifies ambiguous instructions
        4. Maintains the agent's core purpose
        
        Return ONLY the improved prompt, no explanations.
      PROMPT
      
      begin
        response = BedrockService.new(entity: entity).quick_completion(prompt)
        response.strip
      rescue => e
        Rails.logger.error "[EvolutionCycle] Failed to generate improved prompt: #{e.message}"
        nil
      end
    end

    def create_tool_creation_goal(hypothesis)
      AgentGoal.create!(
        entity: entity,
        goal_type: 'expansion',
        title: "Create tools: #{hypothesis[:tools].join(', ')}",
        description: hypothesis[:hypothesis],
        priority: 60,
        source: 'evolution_cycle',
        suggested_actions: ['create_tool'],
        metadata: { tools: hypothesis[:tools], cycle_id: @cycle.id }
      )
    end

    def create_load_balancing_goal(hypothesis)
      AgentGoal.create!(
        entity: entity,
        goal_type: 'maintenance',
        title: "Load balance agents: #{hypothesis[:agents].join(', ')}",
        description: hypothesis[:hypothesis],
        priority: 40,
        source: 'evolution_cycle',
        suggested_actions: ['create_specialist_agent', 'redistribute_tasks'],
        metadata: { agents: hypothesis[:agents], cycle_id: @cycle.id }
      )
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PHASE 5: INTEGRATION
    # ═══════════════════════════════════════════════════════════════════════════

    def run_integration_phase
      Rails.logger.info "[EvolutionCycle] Phase 5: Integration"
      
      # Check for completed experiments from previous cycles
      completed_experiments = AgentAbTest.where(entity: entity, status: 'completed')
        .where('completed_at > ?', 24.hours.ago)
        .where.not(evolution_cycle_id: @cycle.id)
      
      promotions = []
      
      completed_experiments.each do |experiment|
        next unless experiment.variant_significantly_better?
        
        promotion = promote_experiment(experiment)
        promotions << promotion if promotion
      end
      
      @cycle.update!(
        experiments_completed: completed_experiments.count,
        experiments_successful: promotions.count
      )
      
      promotions
    end

    def promote_experiment(experiment)
      metadata = experiment.metadata || {}
      
      case metadata['type']
      when 'prompt_improvement'
        promote_prompt_improvement(experiment)
      else
        nil
      end
    end

    def promote_prompt_improvement(experiment)
      agent = experiment.control_agent
      variant_prompt = experiment.metadata['variant_prompt']
      
      return nil unless agent && variant_prompt
      
      # Apply the improved prompt
      old_prompt = agent.system_prompt
      agent.update!(
        system_prompt: (old_prompt || {}).merge('prompt' => variant_prompt),
        last_evolution_at: Time.current
      )
      agent.increment!(:evolution_count)
      
      # Record lifecycle event
      AgentLifecycleEvent.create!(
        entity: entity,
        agent_plugin: agent,
        event_type: 'promotion',
        description: "Prompt improved via evolution (#{experiment.improvement_percent}% improvement)",
        triggered_by: 'evolution_cycle',
        event_data: {
          experiment_id: experiment.id,
          improvement_percent: experiment.improvement_percent,
          old_prompt_length: old_prompt&.dig('prompt')&.length,
          new_prompt_length: variant_prompt.length
        }
      )
      
      # Mark experiment as promoted
      experiment.update!(
        status: 'promoted',
        promoted_at: Time.current,
        promotion_details: { agent_id: agent.id, change_type: 'prompt_improvement' }
      )
      
      # Record in cycle
      @cycle.record_promotion({
        experiment_id: experiment.id,
        agent: agent.slug,
        type: 'prompt_improvement',
        improvement: experiment.improvement_percent
      })
      
      Rails.logger.info "[EvolutionCycle] Promoted prompt improvement for #{agent.name}: #{experiment.improvement_percent}% improvement"
      
      { agent: agent.slug, experiment_id: experiment.id, improvement: experiment.improvement_percent }
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PHASE 6: DOCUMENTATION
    # ═══════════════════════════════════════════════════════════════════════════

    def run_documentation_phase(analysis, integrations)
      Rails.logger.info "[EvolutionCycle] Phase 6: Documentation"
      
      learnings = []
      
      # Document successful promotions
      integrations.each do |promotion|
        learning = {
          type: 'successful_evolution',
          description: "#{promotion[:agent]} improved by #{promotion[:improvement]}%",
          timestamp: Time.current,
          replicable: true
        }
        learnings << learning
        
        # Archive the learning
        GlobalKnowledgeArchive.archive_learning(
          entity: entity,
          title: "Evolution success: #{promotion[:agent]}",
          content: "Agent #{promotion[:agent]} was improved through prompt optimization, " \
                   "resulting in a #{promotion[:improvement]}% improvement in success rate.",
          knowledge_type: 'lesson_learned',
          metadata: { experiment_id: promotion[:experiment_id] }
        )
      end
      
      # Document patterns from analysis
      if analysis[:anomaly_patterns].present?
        learning = {
          type: 'anomaly_pattern',
          description: "Observed anomaly patterns: #{analysis[:anomaly_patterns][:by_type]}",
          timestamp: Time.current
        }
        learnings << learning
      end
      
      learnings.each { |l| @cycle.record_learning(l) }
    end
  end
end

