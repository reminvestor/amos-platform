require "test_helper"

class TestAgentSystem < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @entity = entities(:one)
    @task_session = TaskSession.create!(
      user: @user,
      status: "active",
      metadata: { test: true }
    )
  end

  test "complete agent workflow from planning to execution" do
    # 1. Test mode detection
    detector = TaskModeDetector.new
    mode = detector.detect_mode("Create a landing page for my product", {})
    assert_equal "interactive", mode[:mode]

    # 2. Test agent creation
    planner = Agents::Specialized::PlannerAgent.new(
      task_session: @task_session
    )
    assert planner.ready?

    # 3. Test planning
    workflow = planner.plan_workflow(
      "Create a simple landing page",
      { user: @user, entity: @entity }
    )
    assert workflow.steps.any?

    # 4. Test execution
    executor = Agents::Specialized::ExecutorAgent.new(
      task_session: @task_session
    )

    result = executor.execute_step(
      workflow.steps.first,
      { user: @user, entity: @entity }
    )
    assert result[:success]

    # 5. Test collaboration
    message = planner.collaborate(executor.id, :insight, {
      content: "Consider using A/B testing"
    })
    assert message

    # 6. Test learning
    learning_engine = Agents::Learning::LearningEngine.new(@entity)
    insights = learning_engine.learn_from_execution(workflow, result)
    assert insights.any?
  end

  test "parallel workflow execution" do
    engine = WorkflowEngineV2.new(@task_session)

    workflow_spec = {
      steps: [
        { id: "step1", type: "tool_call", tool: "get_schema", parallel_group: "data" },
        { id: "step2", type: "tool_call", tool: "list_connections", parallel_group: "data" },
        { id: "step3", type: "tool_call", tool: "get_data", dependencies: [ "step1", "step2" ] }
      ]
    }

    start_time = Time.current
    result = engine.start_workflow(workflow_spec)
    duration = Time.current - start_time

    assert result[:status] == "completed"
    assert duration < 5 # Should be faster than sequential
  end

  test "resilience features" do
    # Test circuit breaker
    breaker = Agents::Resilience::CircuitBreakerRegistry.instance.get("test_service", {
      failure_threshold: 2,
      timeout: 1.second
    })

    # Simulate failures
    2.times do
      assert_raises(StandardError) do
        breaker.call { raise StandardError, "Test error" }
      end
    end

    # Circuit should be open
    assert_raises(Agents::Resilience::CircuitOpenError) do
      breaker.call { "Should not execute" }
    end

    # Test retry policy
    retry_count = 0
    policy = Agents::Resilience::RetryPolicy.new(max_attempts: 3)

    result = policy.execute do
      retry_count += 1
      raise StandardError, "Fail" if retry_count < 3
      "Success"
    end

    assert_equal "Success", result
    assert_equal 3, retry_count
  end

  test "resource management and token tracking" do
    resource_manager = ResourceManager.new(@entity)

    # Test token tracking
    resource_manager.track_tokens(@user, "claude-3-opus", {
      input: 1000,
      output: 500
    })

    stats = resource_manager.token_usage_stats(user: @user)
    assert_equal 1500, stats[:total_tokens]
    assert_equal 1000, stats[:input_tokens]
    assert_equal 500, stats[:output_tokens]

    # Test resource limits
    assert resource_manager.resource_available?(:daily_ai_tokens, 1000)
  end

  test "tool management and permissions" do
    tool_manager = Agents::Tools::ToolManager.instance
    agent_id = SecureRandom.uuid

    # Grant tool access
    tool_manager.grant_tool_access(agent_id, [ "get_data", "create_object" ], {
      usage_limit: 10,
      expires_at: 1.hour.from_now
    })

    # Test permission check
    assert tool_manager.can_use_tool?(agent_id, "get_data")
    assert_not tool_manager.can_use_tool?(agent_id, "delete_object")

    # Test tool sharing
    other_agent_id = SecureRandom.uuid
    result = tool_manager.share_tool(agent_id, other_agent_id, "get_data", {
      duration: 30.minutes
    })

    assert result[:success]
    assert tool_manager.can_use_tool?(other_agent_id, "get_data")
  end

  test "observability and monitoring" do
    tracer = Agents::Observability::DecisionTracer.instance
    monitor = Agents::Observability::PerformanceMonitor.instance

    agent_id = SecureRandom.uuid

    # Start trace
    trace_id = tracer.start_trace(agent_id, :data_analysis)

    # Add reasoning steps
    tracer.add_reasoning(trace_id, :data_gathering, "Collecting user data")
    tracer.add_confidence(trace_id, :data_quality, 0.85)

    # Complete trace
    trace = tracer.complete_trace(trace_id, :success, {
      decision: "Proceed with analysis"
    })

    assert trace[:outcome] == :success
    assert trace[:quality_metrics][:average_confidence] > 0

    # Test performance monitoring
    monitor.record_action(agent_id, :analyze, 1.5, true)
    metrics = monitor.agent_metrics(agent_id)

    assert_equal 1, metrics[:action_count]
    assert_equal 1.0, metrics[:success_rate]
  end
end
