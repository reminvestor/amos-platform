# Agent System Local Testing Guide

## Prerequisites

Before testing the agent system locally, ensure you have:

1. **Redis Running**
   ```bash
   # Start Redis
   redis-server
   
   # Or with Homebrew on Mac
   brew services start redis
   ```

2. **PostgreSQL Running**
   ```bash
   # Ensure PostgreSQL is running
   pg_ctl status
   ```

3. **Environment Variables**
   ```bash
   # Ensure AWS credentials are set for Bedrock
   export AWS_REGION=us-east-1
   export AWS_ACCESS_KEY_ID=your_key
   export AWS_SECRET_ACCESS_KEY=your_secret
   ```

## Testing Methods

### 1. Command Line Testing (Recommended for Quick Tests)

```bash
# Run the comprehensive test suite
rails agents:test_system

# Run interactive console
rails agents:console

# Run performance benchmarks
rails agents:benchmark
```

### 2. Web Interface Testing

1. Start your Rails server:
   ```bash
   rails server
   ```

2. Navigate to: http://localhost:3000/agents/test

3. Use the web interface to:
   - Create different types of agents
   - Plan and execute workflows
   - Test parallel execution
   - Test resilience features
   - Monitor resource usage

### 3. Unit Tests

```bash
# Run agent system tests
rails test test/services/agents/test_agent_system.rb

# Run with verbose output
rails test test/services/agents/test_agent_system.rb -v
```

## Test Scenarios

### Scenario 1: Basic Agent Workflow
1. Create a planner agent
2. Request: "Create a landing page with contact form"
3. Execute the generated workflow
4. Monitor execution through observability

### Scenario 2: Parallel Execution
1. Use the "Parallel Execution" tab in web interface
2. Or run: `rails agents:test_system` and observe timing
3. Compare sequential vs parallel execution times

### Scenario 3: Resilience Testing
1. Test circuit breakers with simulated failures
2. Test retry policies with transient errors
3. Monitor recovery behavior

### Scenario 4: Resource Management
1. Execute multiple workflows
2. Monitor token usage
3. Check cost calculations
4. Test rate limiting

### Scenario 5: Learning & Optimization
1. Execute workflows with different outcomes
2. Test learning engine recommendations
3. Verify performance improvements

## Monitoring During Tests

### 1. Rails Console Monitoring
```ruby
# In rails console
monitor = Agents::Observability::PerformanceMonitor.instance
monitor.system_metrics

# View agent registry
registry = Agents::Communication::AgentRegistry.instance
registry.all_agents

# Check resource usage
rm = ResourceManager.new(Entity.first)
rm.usage_stats
```

### 2. Log Monitoring
```bash
# Watch Rails logs
tail -f log/development.log | grep -E "(Agent|Workflow|Resource)"

# Watch Redis activity
redis-cli MONITOR
```

### 3. Performance Metrics
- Access http://localhost:3000/agents/monitoring for real-time dashboard
- Export reports for analysis

## Common Issues & Solutions

### Issue: "No agents found"
**Solution**: Create agents first using the test interface or console

### Issue: "Circuit breaker open"
**Solution**: Reset circuit breakers:
```ruby
Agents::Resilience::CircuitBreakerRegistry.instance.reset_all
```

### Issue: "Resource limit exceeded"
**Solution**: Reset resource counters or increase limits:
```ruby
Redis.current.flushdb  # Clear all Redis data (careful!)
```

### Issue: "Workflow execution hanging"
**Solution**: Check for deadlocks in parallel execution:
```ruby
WorkflowEngineV2.new(TaskSession.last).shutdown
```

## Advanced Testing

### Custom Workflow Testing
```ruby
# In console
workflow = {
  steps: [
    { id: 'step1', type: 'tool_call', tool: 'get_data', parallel_group: 'fetch' },
    { id: 'step2', type: 'tool_call', tool: 'get_schema', parallel_group: 'fetch' },
    { id: 'step3', type: 'conditional', 
      condition: { expression: 'data_count > 10' },
      then_steps: ['step4'],
      else_steps: ['step5']
    }
  ]
}

session = TaskSession.create!(user: User.first, status: 'active')
engine = WorkflowEngineV2.new(session)
result = engine.start_workflow(workflow)
```

### Load Testing
```ruby
# Simulate multiple concurrent workflows
10.times.map do
  Thread.new do
    planner = Agents::Specialized::PlannerAgent.new
    workflow = planner.plan_workflow("Analyze my campaign data", {})
    # Execute workflow
  end
end.each(&:join)
```

## Debugging Tips

1. **Enable Verbose Logging**
   ```ruby
   Rails.logger.level = :debug
   ```

2. **Trace Specific Agent**
   ```ruby
   tracer = Agents::Observability::DecisionTracer.instance
   tracer.subscribe do |event, trace|
     puts "#{event}: #{trace.inspect}"
   end
   ```

3. **Monitor Memory Usage**
   ```bash
   # In another terminal
   watch -n 1 'ps aux | grep puma | grep -v grep'
   ```

## Next Steps

After successful local testing:

1. Review performance metrics
2. Analyze learning engine insights
3. Optimize workflow templates
4. Plan production deployment
5. Set up monitoring infrastructure

Remember: The agent system is designed to be self-improving. Let it run and learn from executions to see its full potential!




