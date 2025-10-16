module Agents
  class TestController < ApplicationController
    skip_before_action :verify_authenticity_token # For testing only

    def index
      @agents = AgentRegistry.instance.all_agents
      @workflows = WorkflowTemplate.active_with_files
    end

    def create_agent
      role = params[:role] || "executor"

      agent = case role
      when "planner"
        Specialized::PlannerAgent.new(task_session: create_test_session)
      when "executor"
        Specialized::ExecutorAgent.new(task_session: create_test_session)
      when "monitor"
        Specialized::MonitorAgent.new(task_session: create_test_session)
      else
        Base::BaseAgent.new(role: role, task_session: create_test_session)
      end

      render json: {
        success: true,
        agent: {
          id: agent.id,
          role: agent.role,
          state: agent.state,
          capabilities: agent.capabilities
        }
      }
    end

    def plan_workflow
      text = params[:text]
      context = params[:context] || {}

      planner = Specialized::PlannerAgent.new(
        task_session: create_test_session,
        context: context
      )

      workflow = planner.plan_workflow(text, context)

      render json: {
        success: true,
        workflow: {
          name: workflow.name,
          steps: workflow.steps.map { |s| {
            id: s.id,
            name: s.name,
            type: s.type,
            dependencies: s.dependencies
          }}
        }
      }
    rescue => e
      render json: { success: false, error: e.message }
    end

    def execute_workflow
      workflow_data = params[:workflow]

      session = create_test_session
      engine = WorkflowEngineV2.new(session)

      result = engine.start_workflow(workflow_data)

      render json: {
        success: true,
        result: result,
        duration: session.reload.metadata["duration"]
      }
    rescue => e
      render json: { success: false, error: e.message }
    end

    def test_parallel
      # Create a simple parallel workflow
      workflow = {
        steps: [
          {
            id: "fetch1",
            name: "Get Campaigns",
            type: "tool_call",
            config: { tool: "get_data", tool_args: { object_type: "campaign" } },
            parallel_group: "data"
          },
          {
            id: "fetch2",
            name: "Get Contacts",
            type: "tool_call",
            config: { tool: "get_data", tool_args: { object_type: "contact" } },
            parallel_group: "data"
          },
          {
            id: "analyze",
            name: "Analyze Data",
            type: "tool_call",
            config: { tool: "create_dynamic_visualization" },
            dependencies: [ "fetch1", "fetch2" ]
          }
        ]
      }

      session = create_test_session
      engine = WorkflowEngineV2.new(session)

      start_time = Time.current
      result = engine.start_workflow(workflow)
      duration = Time.current - start_time

      render json: {
        success: true,
        duration: duration,
        result: result,
        parallel_speedup: estimate_speedup(workflow, duration)
      }
    end

    def test_resilience
      # Test circuit breaker
      breaker = Resilience::CircuitBreakerRegistry.instance.get("test_service")

      results = []

      # Simulate some calls
      5.times do |i|
        begin
          result = breaker.call do
            # Fail first 3 calls
            raise "Simulated failure" if i < 3
            "Success"
          end
          results << { attempt: i + 1, result: result, state: breaker.status[:state] }
        rescue => e
          results << { attempt: i + 1, error: e.message, state: breaker.status[:state] }
        end
      end

      render json: {
        success: true,
        circuit_breaker_test: results,
        final_status: breaker.status
      }
    end

    def test_learning
      workflow = params[:workflow] || sample_workflow
      outcome = params[:outcome] || { status: "completed", duration: 30 }

      learning_engine = Learning::LearningEngine.new(current_entity)
      insights = learning_engine.learn_from_execution(workflow, outcome)

      # Get recommendations
      recommendations = learning_engine.get_optimization_recommendations(workflow[:type])

      render json: {
        success: true,
        insights: insights,
        recommendations: recommendations,
        performance_analytics: learning_engine.get_performance_analytics(1.hour)
      }
    end

    def agent_communication
      from_id = params[:from_agent_id]
      to_id = params[:to_agent_id]
      message = params[:message] || "Test collaboration message"

      from_agent = AgentRegistry.instance.find(from_id)
      to_agent = AgentRegistry.instance.find(to_id)

      if from_agent && to_agent
        from_agent.collaborate(to_id, :request, { content: message })

        # Check if message was received
        messages = to_agent.check_messages

        render json: {
          success: true,
          sent: true,
          received_messages: messages
        }
      else
        render json: { success: false, error: "Agents not found" }
      end
    end

    def resource_usage
      resource_manager = ResourceManager.new(current_entity)

      # Get various stats
      usage_stats = resource_manager.usage_stats
      token_stats = resource_manager.token_usage_stats(time_range: 24.hours)
      token_breakdown = resource_manager.token_breakdown(group_by: :model)

      render json: {
        success: true,
        usage: usage_stats,
        tokens: token_stats,
        breakdown: token_breakdown,
        cost_estimate: resource_manager.estimate_cost([
          { type: :ai_call, model: "claude-3-opus", tokens: { input: 1000, output: 500 } }
        ])
      }
    end

    def performance_metrics
      monitor = Observability::PerformanceMonitor.instance

      render json: {
        success: true,
        system_metrics: monitor.system_metrics,
        performance_report: monitor.generate_report(24.hours)
      }
    end

    private

    def create_test_session
      @test_session ||= TaskSession.create!(
        user: current_user || User.first,
        status: "active",
        metadata: { test: true, created_by: "test_controller" }
      )
    end

    def sample_workflow
      {
        type: "data_analysis",
        steps: [
          { id: "step1", type: "tool_call", tool: "get_data" },
          { id: "step2", type: "tool_call", tool: "analyze_data" }
        ]
      }
    end

    def estimate_speedup(workflow, actual_duration)
      # Estimate sequential time
      sequential_time = workflow[:steps].size * 2.0 # Assume 2s per step
      sequential_time / actual_duration
    end
  end
end
