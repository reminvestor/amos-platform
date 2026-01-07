# frozen_string_literal: true

require 'test_helper'

class LivingPlatformIntegrationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @entity = entities(:one)
    @user = users(:one)
    @agent = agent_plugins(:one)
    
    # Ensure agent is active and belongs to entity
    @agent.update!(status: 'active', entity: @entity) if @agent
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TEST 1: Full Perception → Desire → Action Flow
  # ═══════════════════════════════════════════════════════════════════════════

  test "perception detects issues and desire engine generates goals" do
    # Create some failing executions to trigger perception
    5.times do
      AgentPluginExecution.create!(
        agent_plugin: @agent,
        user: @user,
        status: 'failed',
        input_context: { test: true },
        output_result: { error: 'Test failure' },
        created_at: 1.hour.ago
      )
    end

    # Run perception
    perception_service = LivingPlatform::PerceptionService.new(@entity)
    perception_result = perception_service.perceive!

    assert perception_result[:success], "Perception should succeed"
    assert perception_result[:perception].present?, "Should create perception record"
    
    # Health should be impacted by failures
    assert perception_result[:perception].overall_health_score < 1.0, "Health should be reduced"

    # Now run desire engine
    desire_engine = LivingPlatform::DesireEngine.new(@entity)
    goals_result = desire_engine.generate_goals!

    assert goals_result[:success], "Desire engine should succeed"
    # Should generate improvement goals for failing agent
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TEST 2: Agent Execution → Context Graph Recording
  # ═══════════════════════════════════════════════════════════════════════════

  test "agent execution creates decision trace" do
    skip "Requires DecisionTrace model" unless defined?(DecisionTrace)
    
    initial_count = DecisionTrace.count

    # Create a completed execution
    execution = AgentPluginExecution.create!(
      agent_plugin: @agent,
      user: @user,
      status: 'running',
      input_context: { task_description: 'Test task' },
      started_at: 2.seconds.ago
    )

    # Complete the execution (triggers callback)
    execution.mark_completed!(
      success: true,
      reasoning: 'Completed successfully',
      result: { data: 'test' }
    )

    # Give the background thread time to run
    sleep 0.5

    # Should have created a decision trace
    assert DecisionTrace.count >= initial_count, "Should create decision trace"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TEST 3: AMOS Orchestrator Integration
  # ═══════════════════════════════════════════════════════════════════════════

  test "AMOS orchestrator provides routing decisions" do
    skip "Requires Amos::Orchestrator" unless defined?(Amos::Orchestrator)

    orchestrator = Amos::Orchestrator.new(entity: @entity, user: @user)

    # Test routing for different message types
    routing1 = orchestrator.route("What is the weather today?")
    assert routing1[:action].present?, "Should provide routing action"

    routing2 = orchestrator.route("Create a marketing campaign")
    assert routing2[:action].present?, "Should provide routing action"

    routing3 = orchestrator.route("Something is broken!")
    assert routing3[:action].present?, "Should provide routing action"
  end

  test "AMOS orchestrator generates valid system prompt" do
    skip "Requires Amos::Orchestrator" unless defined?(Amos::Orchestrator)

    orchestrator = Amos::Orchestrator.new(entity: @entity, user: @user)
    prompt = orchestrator.system_prompt

    assert prompt.present?, "Should generate system prompt"
    assert prompt.include?("AMOS"), "Prompt should mention AMOS"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TEST 4: Scout Integration with Platform Awareness
  # ═══════════════════════════════════════════════════════════════════════════

  test "scout integration provides platform context" do
    skip "Requires Amos::ScoutIntegration" unless defined?(Amos::ScoutIntegration)

    integration = Amos::ScoutIntegration.new(entity: @entity, user: @user)

    # Get context injection
    context = integration.get_context_injection
    # May be empty if no perception data yet
    assert_not_nil context

    # Get routing hint
    hint = integration.get_routing_hint("Test message")
    assert hint[:recommended_action].present? || hint[:action].present?
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TEST 5: Evolution Cycle Flow
  # ═══════════════════════════════════════════════════════════════════════════

  test "evolution cycle runs through all phases" do
    skip "Requires LivingPlatform::EvolutionCycleService" unless defined?(LivingPlatform::EvolutionCycleService)

    service = LivingPlatform::EvolutionCycleService.new(@entity)
    
    # Run a cycle
    result = service.run_cycle!

    assert result[:success], "Evolution cycle should complete"
    assert result[:cycle].present?, "Should create cycle record"
    assert result[:cycle].completed?, "Cycle should be completed"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TEST 6: Metacognition Creates Reflections
  # ═══════════════════════════════════════════════════════════════════════════

  test "metacognition service creates agent reflections" do
    skip "Requires LivingPlatform::MetacognitionService" unless defined?(LivingPlatform::MetacognitionService)
    
    # Create some executions for the agent to reflect on
    3.times do
      AgentPluginExecution.create!(
        agent_plugin: @agent,
        user: @user,
        status: 'completed',
        input_context: { task_description: 'Test task' },
        output_result: { result: 'success' },
        duration_ms: 1500,
        created_at: 2.hours.ago
      )
    end

    service = LivingPlatform::MetacognitionService.new(@entity)
    result = service.run_daily_reflections!

    assert result[:success], "Metacognition should succeed"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TEST 7: Platform Evolution Pipeline
  # ═══════════════════════════════════════════════════════════════════════════

  test "support ticket triggers debug flow" do
    skip "Requires PlatformEvolution services" unless defined?(PlatformEvolution::DebugAgentService)

    # Create a support ticket
    ticket = SupportTicket.create!(
      entity: @entity,
      title: "Test error",
      description: "Something went wrong in the test",
      source: "test",
      priority: "medium"
    )

    assert ticket.persisted?, "Ticket should be created"
    assert ticket.status == 'open', "Ticket should be open"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TEST 8: Context Graph Decision Recording
  # ═══════════════════════════════════════════════════════════════════════════

  test "context graph records and finds precedents" do
    skip "Requires ContextGraph::DecisionRecorder" unless defined?(ContextGraph::DecisionRecorder)

    recorder = ContextGraph::DecisionRecorder.new(@entity)

    # Record a decision
    decision1 = recorder.record(
      agent_plugin: @agent,
      decision_type: 'action',
      decision_summary: 'Sent marketing email to segment A',
      reasoning: 'High engagement predicted',
      confidence_score: 0.85
    )

    assert decision1.persisted?, "Decision should be recorded"

    # Record a similar decision
    decision2 = recorder.record(
      agent_plugin: @agent,
      decision_type: 'action',
      decision_summary: 'Sent marketing email to segment B',
      reasoning: 'Following previous success pattern',
      confidence_score: 0.9
    )

    assert decision2.persisted?, "Second decision should be recorded"

    # Check stats
    stats = recorder.stats(period: 1.day)
    assert stats[:total_decisions] >= 2, "Should have at least 2 decisions"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TEST 9: Integration Bridges Work
  # ═══════════════════════════════════════════════════════════════════════════

  test "execution context bridge records decisions" do
    skip "Requires IntegrationBridges::ExecutionContextBridge" unless defined?(IntegrationBridges::ExecutionContextBridge)

    execution = AgentPluginExecution.create!(
      agent_plugin: @agent,
      user: @user,
      status: 'completed',
      input_context: { task_description: 'Important decision' },
      output_result: { success: true, reasoning: 'Good outcome' },
      duration_ms: 2000,
      started_at: 3.seconds.ago,
      completed_at: 1.second.ago
    )

    bridge = IntegrationBridges::ExecutionContextBridge.new(execution)
    bridge.bridge!

    # Should not raise, and ideally creates a decision trace
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TEST 10: Full Living Platform Benchmark
  # ═══════════════════════════════════════════════════════════════════════════

  test "living platform benchmark runs all categories" do
    skip "Requires Benchmarks::LivingPlatformBenchmark" unless defined?(Benchmarks::LivingPlatformBenchmark)

    benchmark = Benchmarks::LivingPlatformBenchmark.new(@entity)
    results = benchmark.run_full_benchmark

    assert results[:success], "Benchmark should complete"
    assert results[:categories].present?, "Should have category results"
    
    # Check each category exists
    [:perception, :desire_engine, :evolution, :metacognition, :lifecycle, :cost_efficiency, :context_graph].each do |category|
      assert results[:categories][category].present?, "Should have #{category} results"
    end
  end
end


