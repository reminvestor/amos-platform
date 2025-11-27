# frozen_string_literal: true

module Collaboration
  class SimulationRunner
    TASK_DIFFICULTIES = {
      easy: { success_base: 0.9, energy_cost: 5, description: 'Simple lookup or formatting' },
      medium: { success_base: 0.6, energy_cost: 15, description: 'Requires some reasoning' },
      hard: { success_base: 0.3, energy_cost: 25, description: 'Complex multi-step task' },
      expert: { success_base: 0.1, energy_cost: 40, description: 'Requires specialist knowledge' }
    }.freeze

    TASK_TYPES = %w[research analysis creation integration communication].freeze

    attr_reader :results, :entity

    def initialize(entity:)
      @entity = entity
      @results = {
        runs: [],
        summary: {},
        started_at: Time.current
      }
    end

    # ============================================
    # MAIN SIMULATION METHODS
    # ============================================

    def run_full_simulation(num_rounds: 50)
      Rails.logger.info "[Simulation] Starting full simulation with #{num_rounds} rounds"

      reset_agent_states!

      num_rounds.times do |round|
        Rails.logger.info "[Simulation] Round #{round + 1}/#{num_rounds}"
        run_round(round + 1)
      end

      calculate_summary
      @results
    end

    def run_comparison_simulation(num_tasks: 20)
      Rails.logger.info "[Simulation] Running comparison: collaboration ON vs OFF"

      results = {
        with_collaboration: run_task_batch(num_tasks, collaboration_enabled: true),
        without_collaboration: run_task_batch(num_tasks, collaboration_enabled: false),
        improvement: {}
      }

      # Calculate improvement
      with_rate = results[:with_collaboration][:success_rate]
      without_rate = results[:without_collaboration][:success_rate]
      results[:improvement] = {
        success_rate_delta: with_rate - without_rate,
        percentage_improvement: without_rate > 0 ? ((with_rate - without_rate) / without_rate * 100).round(1) : 0
      }

      results
    end

    def run_specialist_matching_test
      Rails.logger.info "[Simulation] Testing specialist matching"

      results = []

      # Create tasks that require specific specialties
      test_cases = [
        { task_type: 'research', task: 'Research competitor pricing strategies', expected_helper: 'web_research_specialist' },
        { task_type: 'analysis', task: 'Analyze campaign performance metrics', expected_helper: 'content_quality_analyzer' },
        { task_type: 'creation', task: 'Create a new landing page design', expected_helper: 'ai_landing_page_creator' },
        { task_type: 'integration', task: 'Set up a new API integration', expected_helper: 'integration_architect' }
      ]

      test_cases.each do |test_case|
        # Pick a non-specialist agent
        non_specialist = AgentPlugin.active
          .where(entity: @entity)
          .where.not(slug: test_case[:expected_helper])
          .first

        next unless non_specialist

        # Simulate the agent deciding whether to ask for help
        tracker = EnergyTracker.new(non_specialist)
        decision = simulate_help_decision(non_specialist, test_case[:task], test_case[:task_type])

        # Find who they would ask
        best_helper = tracker.find_best_helper(test_case[:task])

        results << {
          task_type: test_case[:task_type],
          assigned_agent: non_specialist.slug,
          expected_helper: test_case[:expected_helper],
          actual_helper: best_helper&.dig(:agent)&.slug,
          would_ask_for_help: decision[:should_ask],
          correct_match: best_helper&.dig(:agent)&.slug == test_case[:expected_helper]
        }
      end

      {
        test_cases: results,
        match_rate: results.count { |r| r[:correct_match] }.to_f / results.size,
        ask_rate: results.count { |r| r[:would_ask_for_help] }.to_f / results.size
      }
    end

    def run_energy_stress_test(agent_slug:, num_failures: 5)
      Rails.logger.info "[Simulation] Stress testing agent: #{agent_slug}"

      agent = AgentPlugin.find_by(slug: agent_slug, entity: @entity)
      return { error: 'Agent not found' } unless agent

      initial_energy = agent.current_energy
      energy_history = [initial_energy]
      events = []

      # Simulate failures
      num_failures.times do |i|
        mock_execution = create_mock_execution(agent, 'failed')
        
        pricer = DynamicEnergyPricer.new
        penalty = pricer.failure_penalty(agent, mock_execution)
        
        agent.energy_state.penalize!(penalty, reason: 'simulated_failure', execution: mock_execution)
        
        energy_history << agent.reload.current_energy
        events << {
          round: i + 1,
          type: 'failure',
          penalty: penalty,
          energy_after: agent.current_energy,
          in_school: agent.in_school?
        }

        break if agent.in_school?
      end

      # Check if agent went to school
      enrollment = AgentSchoolEnrollment.where(agent_plugin: agent).order(created_at: :desc).first

      # Simulate recovery (successes)
      unless agent.in_school?
        3.times do |i|
          mock_execution = create_mock_execution(agent, 'completed')
          
          pricer = DynamicEnergyPricer.new
          reward = pricer.task_completion_reward(mock_execution)
          
          agent.energy_state.earn!(reward, reason: 'simulated_success', execution: mock_execution)
          
          energy_history << agent.reload.current_energy
          events << {
            round: num_failures + i + 1,
            type: 'success',
            reward: reward,
            energy_after: agent.current_energy
          }
        end
      end

      {
        agent: agent_slug,
        initial_energy: initial_energy,
        final_energy: agent.current_energy,
        energy_history: energy_history,
        events: events,
        went_to_school: enrollment.present?,
        school_status: enrollment&.status
      }
    end

    def run_relationship_learning_test(num_collaborations: 10)
      Rails.logger.info "[Simulation] Testing relationship learning"

      # Pick two agents
      agents = AgentPlugin.active.where(entity: @entity).limit(2).to_a
      return { error: 'Need at least 2 agents' } if agents.size < 2

      agent_a, agent_b = agents
      
      # Get or create relationship
      relationship = AgentRelationship.find_or_create_by!(
        requester: agent_a,
        helper: agent_b,
        entity: @entity
      )

      initial_score = relationship.compatibility_score
      collaboration_history = []

      num_collaborations.times do |i|
        # Simulate a collaboration
        success = rand < 0.7  # 70% success rate
        quality = success ? rand(3.0..5.0) : rand(1.0..2.5)

        relationship.record_collaboration!(
          success: success,
          quality_rating: quality,
          response_time_ms: rand(1000..10000)
        )

        collaboration_history << {
          round: i + 1,
          success: success,
          quality: quality.round(1),
          compatibility_after: relationship.reload.compatibility_score.round(3)
        }
      end

      {
        agents: [agent_a.slug, agent_b.slug],
        initial_compatibility: initial_score,
        final_compatibility: relationship.compatibility_score,
        improvement: relationship.compatibility_score - initial_score,
        collaborations: collaboration_history,
        successful_count: relationship.successful_collaborations,
        total_count: relationship.total_collaborations
      }
    end

    private

    # ============================================
    # SIMULATION HELPERS
    # ============================================

    def run_round(round_number)
      # Pick a random agent
      agent = AgentPlugin.active.where(entity: @entity).sample
      return unless agent

      # Pick a random task difficulty
      difficulty = TASK_DIFFICULTIES.keys.sample
      task_type = TASK_TYPES.sample

      # Simulate the task
      result = simulate_task(agent, difficulty, task_type, round_number)
      @results[:runs] << result
    end

    def run_task_batch(num_tasks, collaboration_enabled:)
      successes = 0
      collaborations_used = 0
      total_energy_spent = 0

      num_tasks.times do
        agent = AgentPlugin.active.where(entity: @entity).sample
        next unless agent

        difficulty = TASK_DIFFICULTIES.keys.sample
        task_type = TASK_TYPES.sample

        result = simulate_task(
          agent, 
          difficulty, 
          task_type, 
          0,
          collaboration_enabled: collaboration_enabled
        )

        successes += 1 if result[:success]
        collaborations_used += 1 if result[:asked_for_help]
        total_energy_spent += result[:energy_spent] || 0
      end

      {
        total_tasks: num_tasks,
        successes: successes,
        success_rate: (successes.to_f / num_tasks * 100).round(1),
        collaborations_used: collaborations_used,
        collaboration_rate: (collaborations_used.to_f / num_tasks * 100).round(1),
        total_energy_spent: total_energy_spent
      }
    end

    def simulate_task(agent, difficulty, task_type, round, collaboration_enabled: true)
      diff_config = TASK_DIFFICULTIES[difficulty]
      task_description = generate_task_description(task_type, difficulty)

      # Calculate base success probability
      base_success = diff_config[:success_base]

      # Adjust based on agent's specialty match
      specialty_bonus = agent_specialty_match(agent, task_type) * 0.2
      success_prob = [base_success + specialty_bonus, 0.95].min

      # Decide whether to ask for help
      asked_for_help = false
      helper_bonus = 0

      if collaboration_enabled && should_simulate_asking_for_help?(agent, success_prob)
        asked_for_help = true
        helper = find_best_simulated_helper(agent, task_type)
        
        if helper
          # Collaboration bonus
          helper_specialty = agent_specialty_match(helper, task_type)
          helper_bonus = helper_specialty * 0.3
          success_prob = [success_prob + helper_bonus, 0.95].min
        end
      end

      # Determine outcome
      success = rand < success_prob
      quality = success ? rand(0.5..1.0) : rand(0.0..0.3)

      # Record energy changes (simulated, not actual)
      energy_spent = asked_for_help ? 5 : 0
      energy_earned = success ? 25 + (quality * 20) : 0
      energy_lost = success ? 0 : diff_config[:energy_cost]

      {
        round: round,
        agent: agent.slug,
        difficulty: difficulty,
        task_type: task_type,
        task: task_description,
        base_success_prob: base_success.round(2),
        adjusted_success_prob: success_prob.round(2),
        asked_for_help: asked_for_help,
        helper_bonus: helper_bonus.round(2),
        success: success,
        quality: quality.round(2),
        energy_spent: energy_spent,
        energy_change: energy_earned - energy_lost - energy_spent
      }
    end

    def simulate_help_decision(agent, task, task_type)
      # Estimate confidence based on specialty match
      specialty_match = agent_specialty_match(agent, task_type)
      confidence = specialty_match * 100

      # Check decision boundary
      boundary = agent.decision_boundary
      threshold = boundary&.sample_threshold || 50.0

      {
        should_ask: confidence < threshold,
        confidence: confidence,
        threshold: threshold
      }
    end

    def should_simulate_asking_for_help?(agent, success_prob)
      # Simple heuristic: ask for help if success probability is below threshold
      threshold = agent.decision_boundary&.current_threshold || 0.5
      success_prob < threshold
    end

    def find_best_simulated_helper(agent, task_type)
      AgentPlugin.active
        .where(entity: @entity)
        .where.not(id: agent.id)
        .max_by { |a| agent_specialty_match(a, task_type) }
    end

    def agent_specialty_match(agent, task_type)
      # Simple specialty matching based on agent role/capabilities
      specialties = {
        'research' => %w[analyst researcher],
        'analysis' => %w[analyst verifier],
        'creation' => %w[creator engineer architect],
        'integration' => %w[architect engineer],
        'communication' => %w[communicator executor]
      }

      matching_roles = specialties[task_type] || []
      return 0.8 if matching_roles.any? { |r| agent.role&.include?(r) }
      return 0.6 if agent.capabilities&.any? { |c| c.downcase.include?(task_type) }
      0.4 # Base competency
    end

    def generate_task_description(task_type, difficulty)
      templates = {
        research: [
          'Research %s market trends',
          'Find information about %s',
          'Investigate %s competitors'
        ],
        analysis: [
          'Analyze %s performance data',
          'Evaluate %s metrics',
          'Assess %s effectiveness'
        ],
        creation: [
          'Create a %s document',
          'Generate %s content',
          'Build a %s template'
        ],
        integration: [
          'Set up %s integration',
          'Configure %s API',
          'Connect %s service'
        ],
        communication: [
          'Draft %s email',
          'Compose %s message',
          'Write %s notification'
        ]
      }

      difficulty_subjects = {
        easy: %w[simple basic standard],
        medium: %w[detailed comprehensive thorough],
        hard: %w[complex advanced sophisticated],
        expert: %w[enterprise-grade mission-critical specialized]
      }

      template = templates[task_type.to_sym]&.sample || 'Complete %s task'
      subject = difficulty_subjects[difficulty]&.sample || 'general'

      template % subject
    end

    def create_mock_execution(agent, status)
      AgentPluginExecution.create!(
        agent_plugin: agent,
        user: User.first,
        entity: @entity,
        status: status,
        input_context: { 'task_description' => 'Simulated task', 'simulated' => true },
        output_result: status == 'completed' ? { 'result' => 'Success' } : { 'error' => 'Simulated failure' },
        started_at: Time.current,
        completed_at: Time.current
      )
    end

    def reset_agent_states!
      # Optionally reset all agents to starting state
      # For now, we'll just log the current state
      Rails.logger.info "[Simulation] Current agent states preserved"
    end

    def calculate_summary
      runs = @results[:runs]
      return if runs.empty?

      @results[:summary] = {
        total_rounds: runs.size,
        success_rate: (runs.count { |r| r[:success] }.to_f / runs.size * 100).round(1),
        collaboration_rate: (runs.count { |r| r[:asked_for_help] }.to_f / runs.size * 100).round(1),
        avg_quality: (runs.sum { |r| r[:quality] } / runs.size).round(2),
        by_difficulty: TASK_DIFFICULTIES.keys.map do |diff|
          diff_runs = runs.select { |r| r[:difficulty] == diff }
          next if diff_runs.empty?
          {
            difficulty: diff,
            count: diff_runs.size,
            success_rate: (diff_runs.count { |r| r[:success] }.to_f / diff_runs.size * 100).round(1),
            collaboration_rate: (diff_runs.count { |r| r[:asked_for_help] }.to_f / diff_runs.size * 100).round(1)
          }
        end.compact,
        by_task_type: TASK_TYPES.map do |type|
          type_runs = runs.select { |r| r[:task_type] == type }
          next if type_runs.empty?
          {
            task_type: type,
            count: type_runs.size,
            success_rate: (type_runs.count { |r| r[:success] }.to_f / type_runs.size * 100).round(1)
          }
        end.compact,
        completed_at: Time.current,
        duration_seconds: (Time.current - @results[:started_at]).round(1)
      }
    end
  end
end

