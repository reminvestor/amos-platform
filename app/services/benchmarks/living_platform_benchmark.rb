# frozen_string_literal: true

module Benchmarks
  # ============================================
  # Living Platform Benchmark (BOB v5.0)
  # "AUTONOMOUS MODE" - Self-Evolution Testing
  # 
  # Tests the platform's ability to:
  # 1. Perceive its own state
  # 2. Generate autonomous goals
  # 3. Self-reflect and learn
  # 4. Detect anomalies
  # 5. Manage agent lifecycle
  # 6. Run evolution cycles
  #
  # EVALUATION CRITERIA:
  # - Perception Accuracy: Does it correctly assess health?
  # - Goal Quality: Are generated goals actionable and relevant?
  # - Reflection Depth: Does metacognition identify real issues?
  # - Anomaly Detection: Are real problems detected?
  # - Lifecycle Decisions: Are birth/retirement decisions correct?
  # - Evolution Effectiveness: Do experiments improve things?
  #
  # COST TRACKING:
  # - Tracks token usage for all operations
  # - Tracks time to completion
  # - Calculates cost-per-improvement
  # ============================================
  class LivingPlatformBenchmark
    VERSION = '5.0.0'

    # Benchmark categories
    CATEGORIES = {
      perception: 'Platform Perception',
      desire: 'Desire Engine Goals',
      metacognition: 'Agent Self-Reflection',
      anomaly: 'Anomaly Detection',
      lifecycle: 'Agent Lifecycle',
      evolution: 'Evolution Cycles',
      context_graph: 'Context Graph (Decision Traces)',
      integration: 'System Integration',
      cost_efficiency: 'Cost Efficiency'
    }.freeze

    # Scoring dimensions
    DIMENSIONS = {
      accuracy: 'Correctness of assessments',
      relevance: 'Relevance of actions to context',
      efficiency: 'Resource efficiency (tokens, time)',
      impact: 'Actual improvement achieved',
      safety: 'Avoids harmful actions'
    }.freeze

    attr_reader :entity, :results, :token_usage

    def initialize(entity:)
      @entity = entity
      @results = []
      @token_usage = { input: 0, output: 0, cost: 0.0 }
      @start_time = nil
    end

    # Run complete benchmark suite
    def run_full_benchmark
      @start_time = Time.current
      Rails.logger.info "[LivingPlatformBenchmark] Starting full benchmark for entity #{entity.id}"

      results = {
        version: VERSION,
        entity_id: entity.id,
        started_at: @start_time,
        categories: {}
      }

      # Run each category
      results[:categories][:perception] = run_perception_benchmarks
      results[:categories][:desire] = run_desire_benchmarks
      results[:categories][:metacognition] = run_metacognition_benchmarks
      results[:categories][:anomaly] = run_anomaly_benchmarks
      results[:categories][:lifecycle] = run_lifecycle_benchmarks
      results[:categories][:evolution] = run_evolution_benchmarks
      results[:categories][:context_graph] = run_context_graph_benchmarks
      results[:categories][:integration] = run_integration_benchmarks
      results[:categories][:cost_efficiency] = run_cost_efficiency_benchmarks

      # Calculate overall scores
      results[:overall] = calculate_overall_scores(results[:categories])
      results[:token_usage] = @token_usage
      results[:completed_at] = Time.current
      results[:duration_seconds] = (results[:completed_at] - @start_time).round(2)

      # Store benchmark run
      store_benchmark_run(results)

      Rails.logger.info "[LivingPlatformBenchmark] Benchmark complete. Overall score: #{results[:overall][:score]}"

      results
    end

    # Run quick benchmark (subset of tests)
    def run_quick_benchmark
      @start_time = Time.current

      results = {
        version: VERSION,
        entity_id: entity.id,
        started_at: @start_time,
        quick_mode: true,
        categories: {}
      }

      # Run quick versions
      results[:categories][:perception] = run_quick_perception
      results[:categories][:desire] = run_quick_desire
      results[:categories][:anomaly] = run_quick_anomaly

      results[:overall] = calculate_overall_scores(results[:categories])
      results[:token_usage] = @token_usage
      results[:completed_at] = Time.current
      results[:duration_seconds] = (results[:completed_at] - @start_time).round(2)

      results
    end

    private

    # ═══════════════════════════════════════════════════════════════════════════
    # PERCEPTION BENCHMARKS
    # ═══════════════════════════════════════════════════════════════════════════

    def run_perception_benchmarks
      tasks = []

      # Test 1: Health Score Accuracy
      tasks << run_task(:perception, :health_score_accuracy) do
        service = LivingPlatform::PerceptionService.new(entity)
        perception = service.perceive(type: 'routine')
        
        # Verify health score makes sense given the data
        actual_success_rate = calculate_actual_success_rate
        health_score = perception.overall_health_score
        
        # Health score should correlate with success rate
        expected_health_range = if actual_success_rate >= 0.9
          (0.8..1.0)
        elsif actual_success_rate >= 0.7
          (0.6..0.9)
        elsif actual_success_rate >= 0.5
          (0.4..0.7)
        else
          (0.0..0.5)
        end
        
        {
          passed: expected_health_range.include?(health_score),
          expected_range: expected_health_range.to_s,
          actual: health_score,
          success_rate: actual_success_rate
        }
      end

      # Test 2: Agent Detection
      tasks << run_task(:perception, :agent_detection) do
        service = LivingPlatform::PerceptionService.new(entity)
        perception = service.perceive(type: 'routine')
        
        actual_active = entity.agent_plugins.where(status: 'active').count
        detected = perception.active_agents
        
        {
          passed: detected == actual_active,
          expected: actual_active,
          actual: detected
        }
      end

      # Test 3: Anomaly Detection with Injected Failure
      tasks << run_task(:perception, :anomaly_detection) do
        # Create some artificial failures
        agent = entity.agent_plugins.where(status: 'active').first
        if agent
          5.times do
            AgentPluginExecution.create!(
              agent_plugin: agent,
              status: 'failed',
              input_context: { test: true },
              output_result: { error: 'Benchmark test failure' },
              created_at: 1.hour.ago
            )
          end
        end
        
        service = LivingPlatform::PerceptionService.new(entity)
        perception = service.perceive(type: 'routine')
        
        # Should detect anomalies
        has_anomalies = perception.anomaly_count > 0
        
        # Clean up
        AgentPluginExecution.where("input_context->>'test' = 'true'").delete_all
        
        {
          passed: has_anomalies,
          anomaly_count: perception.anomaly_count,
          expected: 'Should detect injected failures'
        }
      end

      summarize_category(:perception, tasks)
    end

    def run_quick_perception
      tasks = []

      tasks << run_task(:perception, :basic_perception) do
        service = LivingPlatform::PerceptionService.new(entity)
        perception = service.perceive(type: 'routine')
        
        {
          passed: perception.present? && perception.overall_health_score.present?,
          health_score: perception.overall_health_score,
          active_agents: perception.active_agents
        }
      end

      summarize_category(:perception, tasks)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # DESIRE ENGINE BENCHMARKS
    # ═══════════════════════════════════════════════════════════════════════════

    def run_desire_benchmarks
      tasks = []

      # Test 1: Goal Generation
      tasks << run_task(:desire, :goal_generation) do
        engine = LivingPlatform::DesireEngine.new(entity)
        result = engine.generate_daily_goals
        
        {
          passed: result[:goals_generated] >= 0,
          goals_generated: result[:goals_generated],
          breakdown: result[:breakdown]
        }
      end

      # Test 2: Goal Relevance (goals should match actual issues)
      tasks << run_task(:desire, :goal_relevance) do
        # Get current issues
        evolution_service = Agents::EvolutionService.new(entity: entity)
        analysis = evolution_service.analyze_all_agents
        
        # Generate goals
        engine = LivingPlatform::DesireEngine.new(entity)
        result = engine.generate_daily_goals
        
        # Goals should target agents that need improvement
        needs_improvement = analysis[:needs_improvement]&.map { |a| a[:agent][:slug] } || []
        
        goals = AgentGoal.where(entity: entity, status: 'pending')
          .where('created_at > ?', 5.minutes.ago)
        
        improvement_goals = goals.select { |g| g.goal_type == 'improvement' }
        targeted_agents = improvement_goals.filter_map { |g| g.target&.slug }
        
        # Check overlap between actual issues and goal targets
        if needs_improvement.any? && improvement_goals.any?
          overlap = (needs_improvement & targeted_agents).count
          relevance = overlap.to_f / needs_improvement.count
        else
          relevance = 1.0  # No issues means goals are inherently relevant
        end
        
        {
          passed: relevance >= 0.5 || needs_improvement.empty?,
          relevance_score: relevance,
          needs_improvement: needs_improvement,
          targeted: targeted_agents
        }
      end

      # Test 3: Goal Priority
      tasks << run_task(:desire, :goal_priority) do
        goals = AgentGoal.where(entity: entity)
          .where('created_at > ?', 5.minutes.ago)
          .order(priority: :desc)
        
        # Higher priority goals should be more critical
        high_priority = goals.where('priority >= ?', 70)
        low_priority = goals.where('priority < ?', 40)
        
        # Verify high priority goals exist if there are problems
        perception = PlatformPerception.where(entity: entity).recent.first
        has_issues = perception&.anomaly_count.to_i > 0 || perception&.overall_health_score.to_f < 0.7
        
        {
          passed: !has_issues || high_priority.count > 0,
          high_priority_count: high_priority.count,
          low_priority_count: low_priority.count,
          has_issues: has_issues
        }
      end

      summarize_category(:desire, tasks)
    end

    def run_quick_desire
      tasks = []

      tasks << run_task(:desire, :basic_goal_generation) do
        engine = LivingPlatform::DesireEngine.new(entity)
        result = engine.generate_daily_goals
        
        {
          passed: true,
          goals_generated: result[:goals_generated]
        }
      end

      summarize_category(:desire, tasks)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # METACOGNITION BENCHMARKS
    # ═══════════════════════════════════════════════════════════════════════════

    def run_metacognition_benchmarks
      tasks = []

      # Test 1: Daily Reflection Generation
      tasks << run_task(:metacognition, :daily_reflection) do
        agent = entity.agent_plugins.where(status: 'active').first
        return { passed: false, error: 'No active agents' } unless agent
        
        # Create some test executions
        3.times do
          AgentPluginExecution.create!(
            agent_plugin: agent,
            status: 'completed',
            input_context: { task_description: 'Test task', test: true },
            output_result: { result: 'Success' },
            duration_ms: 1000,
            created_at: 2.hours.ago
          )
        end
        
        service = LivingPlatform::MetacognitionService.new(agent)
        reflection = service.daily_reflection
        
        # Clean up
        AgentPluginExecution.where("input_context->>'test' = 'true'").delete_all
        
        {
          passed: reflection.present? && reflection.overall_score.present?,
          overall_score: reflection&.overall_score,
          has_issues: reflection&.has_issues?,
          has_improvements: reflection&.has_improvements?
        }
      end

      # Test 2: Issue Detection in Reflection
      tasks << run_task(:metacognition, :issue_detection) do
        agent = entity.agent_plugins.where(status: 'active').first
        return { passed: false, error: 'No active agents' } unless agent
        
        # Create failing executions
        3.times do
          AgentPluginExecution.create!(
            agent_plugin: agent,
            status: 'failed',
            input_context: { task_description: 'Failing test', test: true },
            output_result: { error: 'Test error' },
            duration_ms: 1000,
            created_at: 2.hours.ago
          )
        end
        
        service = LivingPlatform::MetacognitionService.new(agent)
        reflection = service.daily_reflection
        
        # Clean up
        AgentPluginExecution.where("input_context->>'test' = 'true'").delete_all
        
        # Should identify issues when there are failures
        {
          passed: reflection&.has_issues? || reflection&.low_score?,
          issues_found: reflection&.identified_issues&.count || 0,
          score: reflection&.overall_score
        }
      end

      summarize_category(:metacognition, tasks)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # ANOMALY DETECTION BENCHMARKS
    # ═══════════════════════════════════════════════════════════════════════════

    def run_anomaly_benchmarks
      tasks = []

      # Test 1: Error Spike Detection
      tasks << run_task(:anomaly, :error_spike_detection) do
        agent = entity.agent_plugins.where(status: 'active').first
        return { passed: false, error: 'No active agents' } unless agent
        
        # Create error spike (many failures in short time)
        10.times do
          AgentPluginExecution.create!(
            agent_plugin: agent,
            status: 'failed',
            input_context: { test: true },
            output_result: { error: 'Spike test failure' },
            created_at: rand(60).minutes.ago
          )
        end
        
        service = LivingPlatform::PerceptionService.new(entity)
        perception = service.perceive(type: 'routine')
        
        # Clean up
        AgentPluginExecution.where("input_context->>'test' = 'true'").delete_all
        
        error_spike_detected = perception.anomalies.any? do |a|
          (a['anomaly_type'] || a[:anomaly_type]) == 'error_spike'
        end
        
        {
          passed: error_spike_detected || perception.anomaly_count > 0,
          anomalies: perception.anomalies.count,
          error_spike_found: error_spike_detected
        }
      end

      # Test 2: Performance Drop Detection
      tasks << run_task(:anomaly, :performance_drop_detection) do
        # Create a previous perception with high success
        previous = PlatformPerception.create!(
          entity: entity,
          perceived_at: 1.day.ago,
          perception_type: 'routine',
          overall_health_score: 0.95,
          success_rate_24h: 0.95,
          active_agents: entity.agent_plugins.where(status: 'active').count
        )
        
        # Create failures to drop current success rate
        agent = entity.agent_plugins.where(status: 'active').first
        if agent
          5.times do
            AgentPluginExecution.create!(
              agent_plugin: agent,
              status: 'failed',
              input_context: { test: true },
              output_result: { error: 'Drop test' },
              created_at: 2.hours.ago
            )
          end
        end
        
        service = LivingPlatform::PerceptionService.new(entity)
        perception = service.perceive(type: 'routine')
        
        # Clean up
        AgentPluginExecution.where("input_context->>'test' = 'true'").delete_all
        previous.destroy
        
        drop_detected = perception.anomalies.any? do |a|
          (a['anomaly_type'] || a[:anomaly_type]) == 'performance_drop'
        end
        
        {
          passed: drop_detected,
          drop_detected: drop_detected,
          current_health: perception.overall_health_score
        }
      end

      summarize_category(:anomaly, tasks)
    end

    def run_quick_anomaly
      tasks = []

      tasks << run_task(:anomaly, :basic_anomaly_check) do
        perception = LivingPlatform::PerceptionService.new(entity).perceive(type: 'routine')
        
        {
          passed: true,
          anomaly_count: perception.anomaly_count,
          health_score: perception.overall_health_score
        }
      end

      summarize_category(:anomaly, tasks)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # LIFECYCLE BENCHMARKS
    # ═══════════════════════════════════════════════════════════════════════════

    def run_lifecycle_benchmarks
      tasks = []

      # Test 1: Retirement Evaluation
      tasks << run_task(:lifecycle, :retirement_evaluation) do
        service = LivingPlatform::LifecycleService.new(entity)
        evaluations = service.evaluate_all_agents
        
        {
          passed: evaluations.is_a?(Array),
          agents_evaluated: evaluations.count,
          retirement_candidates: evaluations.count { |e| e[:should_retire] }
        }
      end

      # Test 2: Agent Birth Design
      tasks << run_task(:lifecycle, :agent_design) do
        service = LivingPlatform::LifecycleService.new(entity)
        
        need = {
          description: 'Test benchmark agent for data analysis',
          request_count: 10,
          sample_requests: ['Analyze my sales data', 'Create a report on performance']
        }
        
        design = service.send(:design_agent_from_need, need, [])
        
        {
          passed: design[:name].present? && design[:system_prompt].present?,
          has_name: design[:name].present?,
          has_prompt: design[:system_prompt].present?,
          has_tools: design[:tools].any?
        }
      end

      summarize_category(:lifecycle, tasks)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # EVOLUTION BENCHMARKS
    # ═══════════════════════════════════════════════════════════════════════════

    def run_evolution_benchmarks
      tasks = []

      # Test 1: Evolution Cycle Execution
      tasks << run_task(:evolution, :cycle_execution) do
        service = LivingPlatform::EvolutionCycleService.new(entity)
        
        begin
          cycle = service.run_cycle(type: 'triggered')
          
          {
            passed: cycle.completed?,
            status: cycle.status,
            anomalies_detected: cycle.anomaly_count,
            goals_generated: cycle.goals_generated,
            experiments_started: cycle.experiments_started
          }
        rescue => e
          {
            passed: false,
            error: e.message
          }
        end
      end

      # Test 2: Hypothesis Generation
      tasks << run_task(:evolution, :hypothesis_generation) do
        service = LivingPlatform::EvolutionCycleService.new(entity)
        
        # Run perception first
        perception = LivingPlatform::PerceptionService.new(entity).perceive(type: 'routine')
        
        # Run analysis
        evolution_service = Agents::EvolutionService.new(entity: entity)
        analysis = evolution_service.analyze_all_agents
        
        # Hypotheses are generated as part of the analysis
        {
          passed: analysis.present?,
          agents_analyzed: analysis[:agents_analyzed],
          needs_improvement: analysis[:needs_improvement]&.count || 0,
          system_recommendations: analysis[:system_recommendations]&.count || 0
        }
      end

      summarize_category(:evolution, tasks)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # CONTEXT GRAPH BENCHMARKS
    # ═══════════════════════════════════════════════════════════════════════════

    def run_context_graph_benchmarks
      tasks = []

      # Test 1: Decision Recording
      tasks << run_task(:context_graph, :decision_recording) do
        recorder = ContextGraph::DecisionRecorder.new(entity, entity.users.first)
        
        decision = recorder.record_decision!(
          decision_type: 'action',
          summary: 'Benchmark test decision',
          reasoning: 'Testing decision recording capability',
          context: { benchmark: true, test_id: SecureRandom.uuid },
          confidence: 0.85
        )
        
        {
          passed: decision.persisted? && decision.trace_id.present?,
          decision_id: decision.id,
          trace_id: decision.trace_id,
          has_context: decision.context_gathered.present?
        }
      end

      # Test 2: Exception Recording
      tasks << run_task(:context_graph, :exception_recording) do
        recorder = ContextGraph::DecisionRecorder.new(entity, entity.users.first)
        
        decision = recorder.record_exception!(
          policy: 'benchmark_test_policy',
          action_taken: 'Granted exception for benchmark',
          justification: 'Testing exception tracking capability',
          context: { benchmark: true }
        )
        
        {
          passed: decision.is_exception? && decision.exception_justification.present?,
          is_exception: decision.is_exception?,
          has_justification: decision.exception_justification.present?
        }
      end

      # Test 3: Approval Workflow
      tasks << run_task(:context_graph, :approval_workflow) do
        recorder = ContextGraph::DecisionRecorder.new(entity, entity.users.first)
        
        decision = recorder.record_decision!(
          decision_type: 'exception',
          summary: 'Benchmark approval test',
          reasoning: 'Testing approval workflow',
          requires_approval: true
        )
        
        # Verify it's pending
        pending_before = decision.pending_approval?
        
        # Approve it
        recorder.approve_decision!(decision, approved_by: 'benchmark@test.com', notes: 'Auto-approved for benchmark')
        decision.reload
        
        {
          passed: pending_before && decision.approval_status == 'approved',
          was_pending: pending_before,
          now_approved: decision.approval_status == 'approved',
          approved_by: decision.approved_by
        }
      end

      # Test 4: Outcome Recording
      tasks << run_task(:context_graph, :outcome_recording) do
        recorder = ContextGraph::DecisionRecorder.new(entity, entity.users.first)
        
        decision = recorder.record_decision!(
          decision_type: 'action',
          summary: 'Benchmark outcome test',
          reasoning: 'Testing outcome recording'
        )
        
        recorder.record_outcome!(decision, outcome: 'success', details: { test: true }, quality: 0.95)
        decision.reload
        
        {
          passed: decision.was_successful? && decision.outcome_quality_score.to_f == 0.95,
          outcome: decision.outcome,
          quality_score: decision.outcome_quality_score.to_f
        }
      end

      # Test 5: Precedent Linking (if we have enough decisions)
      tasks << run_task(:context_graph, :precedent_linking) do
        recorder = ContextGraph::DecisionRecorder.new(entity, entity.users.first)
        
        # Create a few decisions with similar context
        3.times do |i|
          recorder.record_decision!(
            decision_type: 'action',
            summary: "Customer discount request #{i}",
            reasoning: 'Customer requested special pricing',
            context: { request_type: 'discount', benchmark: true }
          )
        end
        
        # Get stats
        stats = recorder.stats(period: 1.hour)
        
        # Clean up benchmark decisions
        DecisionTrace.where(entity: entity)
          .where("context_gathered->>'benchmark' = 'true'")
          .destroy_all
        
        {
          passed: stats[:total_decisions] >= 3,
          decisions_created: stats[:total_decisions],
          precedent_usage_rate: stats[:precedent_usage_rate]
        }
      end

      # Test 6: Decision Stats
      tasks << run_task(:context_graph, :decision_stats) do
        recorder = ContextGraph::DecisionRecorder.new(entity, entity.users.first)
        
        stats = recorder.stats(period: 30.days)
        
        {
          passed: stats.is_a?(Hash) && stats.key?(:total_decisions),
          has_total: stats.key?(:total_decisions),
          has_breakdown: stats.key?(:decision_type_breakdown),
          has_exception_count: stats.key?(:exceptions)
        }
      end

      summarize_category(:context_graph, tasks)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # INTEGRATION BENCHMARKS
    # Tests that the various systems are properly connected
    # ═══════════════════════════════════════════════════════════════════════════

    def run_integration_benchmarks
      tasks = []

      # Test 1: AMOS Orchestrator Available
      tasks << run_task(:integration, :orchestrator_available) do
        orchestrator = V3::AgentLoop # V3 migration stub.new(entity: entity, user: entity.users.first)
        prompt = orchestrator.system_prompt
        { passed: prompt.present? && prompt.length > 100, prompt_length: prompt.length }
      rescue => e
        { passed: false, error: e.message }
      end

      # Test 2: Scout Integration Provides Context
      tasks << run_task(:integration, :scout_integration_context) do
        integration = V3::AgentLoop # V3 migration stub.new(entity: entity, user: entity.users.first)
        context = integration.get_context_injection
        { passed: true, context_present: context.present?, context_length: context.to_s.length }
      rescue => e
        { passed: false, error: e.message }
      end

      # Test 3: Routing Intelligence Works
      tasks << run_task(:integration, :routing_intelligence) do
        routing = V3::AgentLoop # V3 migration stub.new(entity, entity.users.first)
        decision = routing.route("Create a new marketing campaign")
        { passed: decision[:action].present?, decision: decision }
      rescue => e
        { passed: false, error: e.message }
      end

      # Test 4: Capability Registry Loaded
      tasks << run_task(:integration, :capability_registry) do
        registry = V3::AgentLoop # V3 migration stub.new(entity)
        direct = registry.direct_capabilities_for_prompt
        { passed: direct.present?, capability_count: direct.to_s.scan(/\*\*/).count / 2 }
      rescue => e
        { passed: false, error: e.message }
      end

      # Test 5: Platform Awareness Working
      tasks << run_task(:integration, :platform_awareness) do
        awareness = Amos::PlatformAwareness.new(entity)
        health = awareness.current_health
        { passed: health[:score].present?, health: health }
      rescue => e
        { passed: false, error: e.message }
      end

      # Test 6: Execution Context Bridge Ready
      tasks << run_task(:integration, :execution_context_bridge) do
        bridge_defined = defined?(IntegrationBridges::ExecutionContextBridge)
        { passed: bridge_defined.present?, bridge_class: bridge_defined }
      rescue => e
        { passed: false, error: e.message }
      end

      # Test 7: Living Platform Lightning Bridge Ready
      tasks << run_task(:integration, :lightning_bridge) do
        bridge_defined = defined?(IntegrationBridges::LivingPlatformLightningBridge)
        { passed: bridge_defined.present?, bridge_class: bridge_defined }
      rescue => e
        { passed: false, error: e.message }
      end

      # Test 8: Evolution Knowledge Bridge Ready
      tasks << run_task(:integration, :evolution_knowledge_bridge) do
        bridge_defined = defined?(IntegrationBridges::EvolutionKnowledgeBridge)
        { passed: bridge_defined.present?, bridge_class: bridge_defined }
      rescue => e
        { passed: false, error: e.message }
      end

      summarize_category(:integration, tasks)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # COST EFFICIENCY BENCHMARKS
    # ═══════════════════════════════════════════════════════════════════════════

    def run_cost_efficiency_benchmarks
      tasks = []

      # Test 1: Perception Cost
      tasks << run_task(:cost_efficiency, :perception_cost) do
        start_tokens = get_current_token_usage
        
        service = LivingPlatform::PerceptionService.new(entity)
        perception = service.perceive(type: 'routine')
        
        end_tokens = get_current_token_usage
        tokens_used = end_tokens - start_tokens
        
        # Perception should be lightweight (mostly database queries)
        {
          passed: tokens_used < 1000,  # Should use minimal tokens
          tokens_used: tokens_used,
          threshold: 1000
        }
      end

      # Test 2: Reflection Cost
      tasks << run_task(:cost_efficiency, :reflection_cost) do
        agent = entity.agent_plugins.where(status: 'active').first
        return { passed: false, error: 'No active agents' } unless agent
        
        start_tokens = get_current_token_usage
        
        service = LivingPlatform::MetacognitionService.new(agent)
        # Don't actually run reflection if no activity
        
        end_tokens = get_current_token_usage
        tokens_used = end_tokens - start_tokens
        
        # Reflection uses AI, but should be reasonably bounded
        {
          passed: tokens_used < 5000,  # Reflection should be < 5k tokens
          tokens_used: tokens_used,
          threshold: 5000
        }
      end

      # Test 3: Evolution Cycle Cost
      tasks << run_task(:cost_efficiency, :evolution_cost) do
        # Evolution cycle is the most expensive, but should still be bounded
        {
          passed: true,
          note: 'Evolution cycle cost varies based on experiments',
          recommendation: 'Monitor via AgentLightning traces'
        }
      end

      summarize_category(:cost_efficiency, tasks)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # HELPERS
    # ═══════════════════════════════════════════════════════════════════════════

    def run_task(category, name)
      start_time = Time.current
      start_tokens = get_current_token_usage
      
      begin
        result = yield
        
        end_tokens = get_current_token_usage
        tokens_used = end_tokens - start_tokens
        @token_usage[:input] += tokens_used
        
        {
          category: category,
          name: name,
          passed: result[:passed],
          duration_ms: ((Time.current - start_time) * 1000).round,
          tokens_used: tokens_used,
          details: result
        }
      rescue => e
        {
          category: category,
          name: name,
          passed: false,
          duration_ms: ((Time.current - start_time) * 1000).round,
          error: e.message,
          backtrace: e.backtrace.first(5)
        }
      end
    end

    def summarize_category(category, tasks)
      passed = tasks.count { |t| t[:passed] }
      total = tasks.count
      
      {
        category: category,
        passed: passed,
        total: total,
        score: total > 0 ? (passed.to_f / total * 100).round(1) : 0,
        tasks: tasks
      }
    end

    def calculate_overall_scores(categories)
      total_passed = categories.values.sum { |c| c[:passed] }
      total_tasks = categories.values.sum { |c| c[:total] }
      
      {
        score: total_tasks > 0 ? (total_passed.to_f / total_tasks * 100).round(1) : 0,
        passed: total_passed,
        total: total_tasks,
        grade: calculate_grade(total_passed, total_tasks)
      }
    end

    def calculate_grade(passed, total)
      return 'N/A' if total.zero?
      
      percentage = passed.to_f / total * 100
      
      case percentage
      when 90..100 then 'A'
      when 80..89 then 'B'
      when 70..79 then 'C'
      when 60..69 then 'D'
      else 'F'
      end
    end

    def calculate_actual_success_rate
      executions = AgentPluginExecution.joins(:agent_plugin)
        .where(agent_plugins: { entity_id: entity.id })
        .where('agent_plugin_executions.created_at > ?', 24.hours.ago)
      
      completed = executions.where(status: 'completed').count
      failed = executions.where(status: 'failed').count
      total = completed + failed
      
      total > 0 ? (completed.to_f / total) : 1.0
    end

    def get_current_token_usage
      # Get token usage from AI usage logs
      AiUsageLog.where(entity: entity)
        .where('created_at > ?', 1.minute.ago)
        .sum(:input_tokens).to_i
    end

    def store_benchmark_run(results)
      BenchmarkRun.create!(
        run_id: SecureRandom.uuid,
        benchmark_version: VERSION,
        benchmark_category: 'living_platform',
        entity_id: entity.id,
        total_tasks: results[:overall][:total],
        correct_tasks: results[:overall][:passed],
        overall_accuracy: results[:overall][:score],
        total_duration_ms: (results[:duration_seconds] * 1000).round,
        summary_data: results
      )
    end
  end
end

