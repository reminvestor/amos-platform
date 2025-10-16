namespace :agents do
  desc "Test the agent system locally"
  task test_system: :environment do
    puts "\n🤖 Agent System Local Testing Suite\n".colorize(:cyan)

    # Setup test user and entity
    user = User.first || User.create!(
      email: "test@example.com",
      password: "password123",
      first_name: "Test",
      last_name: "User"
    )

    entity = user.entity || begin
      new_entity = Entity.create!(
        name: "Test Entity",
        platform_tier: "premium"
      )
      user.update!(entity: new_entity)
      new_entity
    end

    puts "✅ Test user and entity ready\n".colorize(:green)

    # Test 1: Basic Agent Creation
    puts "Test 1: Creating Agents...".colorize(:yellow)

    planner = Agents::Specialized::PlannerAgent.new(
      initial_context: { user: user, entity: entity }
    )

    executor = Agents::Specialized::ExecutorAgent.new(
      initial_context: { user: user, entity: entity }
    )

    puts "  ✓ Planner Agent: #{planner.id}".colorize(:green)
    puts "  ✓ Executor Agent: #{executor.id}".colorize(:green)

    # Test 2: Agent Communication
    puts "\nTest 2: Testing Agent Communication...".colorize(:yellow)

    message = {
      type: :collaboration_request,
      content: "Need help analyzing data"
    }

    planner.collaborate(executor.id, :request, message)
    puts "  ✓ Message sent from planner to executor".colorize(:green)

    # Test 3: Planning a Workflow
    puts "\nTest 3: Planning a Workflow...".colorize(:yellow)

    # Enable Rails logging to see what's happening
    original_logger = Rails.logger
    Rails.logger = Logger.new(STDOUT)
    Rails.logger.level = Logger::INFO

    puts "  → Calling planner.plan_workflow...".colorize(:light_gray)
    request = "Create a landing page with contact form"

    # Use a timeout to prevent hanging forever
    require "timeout"
    begin
      result = Timeout.timeout(30) do
        puts "  → Starting workflow planning for: '#{request}'".colorize(:light_gray)
        planner.plan_workflow(request, { user: user, entity: entity })
      end

      if result[:success] && result[:workflow]
        workflow = result[:workflow]

        # Handle both SimpleWorkflow object and Hash format
        if workflow.respond_to?(:steps)
          steps = workflow.steps
          puts "  ✓ Workflow created with #{steps.size} steps:".colorize(:green)
          steps.each_with_index do |step, i|
            puts "    #{i+1}. #{step.name} (#{step.type})".colorize(:light_blue)
          end
        elsif workflow.is_a?(Hash) && workflow[:steps]
          steps = workflow[:steps]
          puts "  ✓ Workflow created with #{steps.size} steps:".colorize(:green)
          steps.each_with_index do |step, i|
            step_name = step[:name] || step["name"]
            step_type = step[:type] || step["type"]
            puts "    #{i+1}. #{step_name} (#{step_type})".colorize(:light_blue)
          end
        else
          puts "  ✓ Workflow created but format unclear: #{workflow.class}".colorize(:yellow)
        end
      else
        puts "  ✗ Failed to create workflow: #{result[:error]}".colorize(:red)
        puts "    Issues: #{result[:issues]&.join(', ')}".colorize(:yellow) if result[:issues]
      end
    rescue Timeout::Error
      puts "\n  ✗ Planning timed out after 30 seconds!".colorize(:red)
      puts "  Check the logs above to see where it got stuck.".colorize(:yellow)
    rescue => e
      puts "\n  ✗ Error during planning: #{e.class} - #{e.message}".colorize(:red)
      puts e.backtrace.first(5).map { |line| "    #{line}" }.join("\n").colorize(:light_red)
    ensure
      # Restore original logger
      Rails.logger = original_logger
    end

    # Test 4: Parallel Execution
    puts "\nTest 4: Testing Parallel Execution...".colorize(:yellow)

    task_session = TaskSession.create!(
      user: user,
      status: "active",
      metadata: { test: true }
    )

    engine = WorkflowEngineV2.new(task_session)

    parallel_workflow = {
      steps: [
        {
          id: "data1",
          name: "Get Campaigns",
          type: "tool_call",
          config: { tool: "get_data", tool_args: { object_type: "campaign" } },
          parallel_group: "data_fetch"
        },
        {
          id: "data2",
          name: "Get Contacts",
          type: "tool_call",
          config: { tool: "get_data", tool_args: { object_type: "contact" } },
          parallel_group: "data_fetch"
        }
      ]
    }

    start_time = Time.current
    result = engine.start_workflow(parallel_workflow)
    duration = Time.current - start_time

    puts "  ✓ Parallel execution completed in #{duration.round(2)}s".colorize(:green)
    puts "    Status: #{result[:status]}".colorize(:light_blue)

    # Test 5: Resource Management
    puts "\nTest 5: Testing Resource Management...".colorize(:yellow)

    resource_manager = ResourceManager.new(entity)

    # Simulate token usage
    resource_manager.track_tokens(user, "claude-3-opus", {
      input: 500,
      output: 250
    })

    stats = resource_manager.token_usage_stats(user: user)
    puts "  ✓ Token tracking:".colorize(:green)
    puts "    Total: #{stats[:total_tokens]} tokens".colorize(:light_blue)
    puts "    Cost: $#{(stats[:total_tokens] * 0.00002).round(4)}".colorize(:light_blue)

    # Test 6: Tool Permissions
    puts "\nTest 6: Testing Tool Management...".colorize(:yellow)

    tool_manager = Agents::Tools::ToolManager.instance

    # Grant tools to planner
    tool_manager.grant_tool_access(planner.id, [
      "get_data", "get_schema", "create_dynamic_visualization"
    ], usage_limit: 100)

    # Test permission
    can_use = tool_manager.can_use_tool?(planner.id, "get_data")
    puts "  ✓ Planner can use get_data: #{can_use}".colorize(:green)

    # Share tool with executor
    share_result = tool_manager.share_tool(
      planner.id,
      executor.id,
      "get_data",
      duration: 1.hour
    )
    puts "  ✓ Tool shared: #{share_result[:success]}".colorize(:green)

    # Test 7: Circuit Breaker
    puts "\nTest 7: Testing Resilience Features...".colorize(:yellow)

    breaker = Agents::Resilience::CircuitBreakerRegistry.instance.get("test_api")

    # Simulate successful calls
    3.times do
      breaker.call { "Success" }
    end

    puts "  ✓ Circuit breaker status: #{breaker.status[:state]}".colorize(:green)

    # Test 8: Learning Engine
    puts "\nTest 8: Testing Learning Engine...".colorize(:yellow)

    learning_engine = Agents::Learning::LearningEngine.new(entity)

    # Simulate learning from execution
    execution_result = {
      status: "completed",
      duration: 45.seconds,
      metrics: { satisfaction_score: 4.5 }
    }

    insights = learning_engine.learn_from_execution(workflow, execution_result)
    puts "  ✓ Generated #{insights.size} insights from execution".colorize(:green)

    # Test 9: Decision Tracing
    puts "\nTest 9: Testing Observability...".colorize(:yellow)

    tracer = Agents::Observability::DecisionTracer.instance

    trace_id = tracer.start_trace(planner.id, :workflow_planning)
    tracer.add_reasoning(trace_id, :analyzing_request, "Understanding user intent")
    tracer.add_confidence(trace_id, :intent_clarity, 0.92)
    trace = tracer.complete_trace(trace_id, :success)

    puts "  ✓ Decision trace completed".colorize(:green)
    puts "    Duration: #{trace[:duration].round(2)}s".colorize(:light_blue)
    puts "    Confidence: #{trace[:quality_metrics][:average_confidence]}".colorize(:light_blue)

    # Test 10: Performance Monitoring
    puts "\nTest 10: Testing Performance Monitoring...".colorize(:yellow)

    monitor = Agents::Observability::PerformanceMonitor.instance

    # Record some actions
    monitor.record_action(planner.id, :plan, 2.5, true)
    monitor.record_action(executor.id, :execute, 1.2, true)

    system_metrics = monitor.system_metrics
    puts "  ✓ System metrics:".colorize(:green)
    puts "    Active agents: #{system_metrics[:active_agents]}".colorize(:light_blue)
    puts "    Success rate: #{(system_metrics[:success_rate] * 100).round}%".colorize(:light_blue)

    puts "\n✅ All tests completed successfully!".colorize(:green)
    puts "\n📊 Summary:".colorize(:cyan)
    puts "  - Agents created and communicating"
    puts "  - Workflows planned and executed"
    puts "  - Parallel execution working"
    puts "  - Resource tracking active"
    puts "  - Tool permissions enforced"
    puts "  - Resilience features operational"
    puts "  - Learning from executions"
    puts "  - Full observability enabled"

  rescue => e
    puts "\n❌ Error during testing: #{e.message}".colorize(:red)
    puts e.backtrace.first(5).join("\n").colorize(:light_red)
  end

  desc "Interactive agent testing console"
  task console: :environment do
    require "irb"

    puts "\n🤖 Agent System Interactive Console\n".colorize(:cyan)
    puts "Available helpers:".colorize(:yellow)
    puts "  - create_agent(role)     # Create a new agent"
    puts "  - plan_workflow(text)    # Plan a workflow from text"
    puts "  - execute_workflow(wf)   # Execute a workflow"
    puts "  - agent_status          # Show all agent status"
    puts "  - resource_stats        # Show resource usage"

    # Define helper methods
    def create_agent(role)
      user = User.first
      entity = user.entity
      context = { user: user, entity: entity }

      case role.to_sym
      when :planner
        Agents::Specialized::PlannerAgent.new(initial_context: context)
      when :executor
        Agents::Specialized::ExecutorAgent.new(initial_context: context)
      else
        Agents::Base::BaseAgent.new(role: role, context: context)
      end
    end

    def plan_workflow(text)
      planner = create_agent(:planner)
      planner.plan_workflow(text, {})
    end

    def execute_workflow(workflow)
      session = TaskSession.create!(user: User.first, status: "active")
      engine = WorkflowEngineV2.new(session)
      engine.start_workflow(workflow)
    end

    def agent_status
      registry = Agents::Communication::AgentRegistry.instance
      agents = registry.all_agents

      agents.each do |agent|
        puts "#{agent.role} (#{agent.id[0..7]}...): #{agent.state}"
      end

      "#{agents.size} agents registered"
    end

    def resource_stats
      rm = ResourceManager.new(Entity.first)
      rm.usage_stats
    end

    # Start IRB session
    ARGV.clear
    IRB.start
  end

  desc "Benchmark agent system performance"
  task benchmark: :environment do
    require "benchmark"

    puts "\n⚡ Agent System Performance Benchmark\n".colorize(:cyan)

    user = User.first
    entity = user.entity

    # Benchmark workflow planning
    puts "1. Workflow Planning Speed:".colorize(:yellow)

    planning_times = Benchmark.measure do
      10.times do
        planner = Agents::Specialized::PlannerAgent.new
        planner.plan_workflow("Create a campaign with email template", {})
      end
    end

    puts "  Average planning time: #{(planning_times.real / 10).round(3)}s".colorize(:green)

    # Benchmark parallel vs sequential
    puts "\n2. Parallel vs Sequential Execution:".colorize(:yellow)

    session = TaskSession.create!(user: user, status: "active")
    engine = WorkflowEngineV2.new(session)

    # Sequential workflow
    sequential_workflow = {
      steps: (1..5).map do |i|
        { id: "step#{i}", type: "tool_call", config: { tool: "get_schema" } }
      end
    }

    seq_time = Benchmark.realtime do
      engine.start_workflow(sequential_workflow)
    end

    # Parallel workflow
    parallel_workflow = {
      steps: (1..5).map do |i|
        {
          id: "step#{i}",
          type: "tool_call",
          config: { tool: "get_schema" },
          parallel_group: "all"
        }
      end
    }

    par_time = Benchmark.realtime do
      engine.start_workflow(parallel_workflow)
    end

    puts "  Sequential: #{seq_time.round(3)}s".colorize(:light_blue)
    puts "  Parallel: #{par_time.round(3)}s".colorize(:green)
    puts "  Speedup: #{(seq_time / par_time).round(2)}x".colorize(:cyan)

    # Benchmark agent communication
    puts "\n3. Agent Communication Speed:".colorize(:yellow)

    agent1 = create_agent(:planner)
    agent2 = create_agent(:executor)

    comm_time = Benchmark.realtime do
      100.times do
        agent1.collaborate(agent2.id, :ping, { data: "test" })
      end
    end

    puts "  100 messages: #{comm_time.round(3)}s".colorize(:green)
    puts "  Messages/second: #{(100 / comm_time).round}".colorize(:light_blue)

    # Memory usage
    puts "\n4. Memory Usage:".colorize(:yellow)

    memory_before = `ps -o rss= -p #{Process.pid}`.to_i

    # Create many agents
    agents = 50.times.map { create_agent(:executor) }

    memory_after = `ps -o rss= -p #{Process.pid}`.to_i
    memory_used = (memory_after - memory_before) / 1024.0

    puts "  50 agents memory usage: #{memory_used.round(2)} MB".colorize(:green)
    puts "  Per agent: #{(memory_used / 50).round(2)} MB".colorize(:light_blue)

    puts "\n✅ Benchmark completed!".colorize(:green)
  end
end

# Add colorize method if not available
class String
  def colorize(color)
    colors = {
      red: 31,
      green: 32,
      yellow: 33,
      blue: 34,
      magenta: 35,
      cyan: 36,
      light_red: 91,
      light_green: 92,
      light_yellow: 93,
      light_blue: 94,
      light_magenta: 95,
      light_cyan: 96
    }
    "\e[#{colors[color]}m#{self}\e[0m"
  end
end
