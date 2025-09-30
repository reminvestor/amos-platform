# Nimble Multi-Agent Task Planning & Execution System
## Comprehensive Implementation Plan

### Executive Summary

This plan outlines the transformation of the current system into a truly nimble, production-ready multi-agent task planning and execution system. Based on a comprehensive analysis of the existing codebase, we'll build upon strong foundations while addressing critical gaps.

---

## 🎯 Current System Analysis

### Strengths
1. **Solid Foundation**
   - Modular tool system (`ToolCatalog`) with 14+ specialized tools
   - Workflow engine with step-based execution
   - Task persistence via `TaskSession` and `TaskEvent` models
   - LLM-powered planning (`PlannerAgentService`)
   - Template-based workflows (YAML)
   - Observability service for metrics

2. **Good Architecture Patterns**
   - V2 modular tools with `BaseTool` abstraction
   - Event-sourced task tracking
   - Canvas-based UI system
   - Interactive/Autonomous mode detection

### Critical Gaps
1. **No Real Agent Framework** - Agents are just roles, not autonomous entities
2. **Limited Execution** - Sequential only, no parallel/conditional execution
3. **No Learning Loop** - System doesn't improve from experience
4. **Basic Error Handling** - No retry strategies or self-healing
5. **No Resource Management** - Unbounded API costs
6. **Limited Context Sharing** - Agents can't effectively collaborate

---

## 🏗️ Proposed Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────────────┐
│                        Orchestration Layer                       │
├─────────────────────────────────────────────────────────────────┤
│  TaskOrchestrator  │  PlanCompiler  │  ExecutionEngine         │
├─────────────────────────────────────────────────────────────────┤
│                         Agent Framework                          │
├─────────────────────────────────────────────────────────────────┤
│  BaseAgent  │  PlannerAgent  │  ExecutorAgent  │  GuardAgent   │
├─────────────────────────────────────────────────────────────────┤
│                      Shared Intelligence                         │
├─────────────────────────────────────────────────────────────────┤
│  ContextManager  │  MemoryStore  │  LearningEngine  │  RAG     │
├─────────────────────────────────────────────────────────────────┤
│                     Execution & Tools                            │
├─────────────────────────────────────────────────────────────────┤
│  WorkflowEngineV2  │  ToolCatalog  │  ResourceManager          │
├─────────────────────────────────────────────────────────────────┤
│                    Persistence & Events                          │
├─────────────────────────────────────────────────────────────────┤
│  TaskSession  │  TaskEvent  │  AgentMemory  │  WorkflowCache   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📋 Implementation Phases

### Phase 1: Enhanced Agent Framework (Week 1-2)

#### 1.1 Create True Agent Classes

```ruby
# app/services/agents/base_agent.rb
class Agents::BaseAgent
  attr_reader :id, :role, :capabilities, :memory, :context
  
  def initialize(role:, capabilities:, context:)
    @id = SecureRandom.uuid
    @role = role
    @capabilities = capabilities
    @memory = AgentMemory.new(agent_id: @id)
    @context = context
    @state = :idle
  end
  
  def think(input)
    # Agent reasoning with memory and context
  end
  
  def act(decision)
    # Execute decision with available tools
  end
  
  def learn(outcome)
    # Update memory based on outcomes
  end
  
  def collaborate(other_agent, message)
    # Inter-agent communication
  end
end
```

#### 1.2 Specialized Agent Implementations

- **PlannerAgent**: Enhanced with template learning, cost estimation
- **ExecutorAgent**: Tool execution with retry strategies  
- **AnalystAgent**: Data aggregation and insights
- **GuardAgent**: Security, rate limiting, cost control
- **MonitorAgent**: Observability and intervention

#### 1.3 Agent Registry & Factory

```ruby
# app/services/agents/agent_registry.rb
class Agents::AgentRegistry
  def self.spawn_agent(role, context)
    agent_class = registry[role]
    agent = agent_class.new(context: context)
    active_agents[agent.id] = agent
    agent
  end
end
```

### Phase 2: Advanced Workflow Engine (Week 2-3)

#### 2.1 Parallel Execution Support

```ruby
# app/services/workflow_engine_v2.rb
class WorkflowEngineV2 < WorkflowEngine
  def execute_parallel_steps(step_group)
    promises = step_group.map do |step|
      Concurrent::Promise.execute do
        execute_step(step)
      end
    end
    
    Concurrent::Promise.zip(*promises).value
  end
end
```

#### 2.2 Conditional & Loop Support

```yaml
# Workflow template with advanced flow control
steps:
  - id: "check_data"
    type: "conditional"
    condition:
      expression: "data_count > 1000"
      then_steps: ["batch_process"]
      else_steps: ["single_process"]
      
  - id: "batch_process"
    type: "loop"
    iterator:
      over: "data_batches"
      parallel: true
      max_concurrent: 5
    body:
      - id: "process_batch"
        type: "tool_call"
        tool: "process_data_batch"
```

#### 2.3 Dynamic Replanning

```ruby
class WorkflowEngineV2
  def handle_step_failure(step, error)
    # Ask planner to create recovery plan
    recovery_plan = @planner_agent.create_recovery_plan(
      failed_step: step,
      error: error,
      context: current_context
    )
    
    inject_steps(recovery_plan.steps)
  end
end
```

### Phase 3: Shared Context & Collaboration (Week 3-4)

#### 3.1 Context Manager (Blackboard Pattern)

```ruby
# app/services/context_manager.rb
class ContextManager
  def initialize(task_session)
    @task_session = task_session
    @blackboard = Redis.new
    @subscriptions = {}
  end
  
  def write(key, value, agent_id)
    data = { value: value, agent_id: agent_id, timestamp: Time.current }
    @blackboard.hset(context_key, key, data.to_json)
    notify_subscribers(key, data)
  end
  
  def read(key)
    JSON.parse(@blackboard.hget(context_key, key))
  end
  
  def subscribe(pattern, agent_id, &callback)
    @subscriptions[pattern] ||= []
    @subscriptions[pattern] << { agent_id: agent_id, callback: callback }
  end
end
```

#### 3.2 Agent Communication Protocol

```ruby
class Agents::BaseAgent
  def send_message(recipient_id, message_type, content)
    AgentMessage.create!(
      sender_id: @id,
      recipient_id: recipient_id,
      message_type: message_type,
      content: content,
      task_session_id: @context.task_session_id
    )
  end
  
  def handle_message(message)
    case message.message_type
    when 'help_request'
      assist_with_task(message)
    when 'insight'
      incorporate_insight(message)
    end
  end
end
```

### Phase 4: Learning & Improvement (Week 4-5)

#### 4.1 Feedback Collection

```ruby
# app/models/workflow_feedback.rb
class WorkflowFeedback < ApplicationRecord
  belongs_to :task_session
  
  # Capture what worked and what didn't
  store_accessor :feedback_data, :success_factors, :failure_points, 
                 :user_modifications, :performance_metrics
end
```

#### 4.2 Learning Engine

```ruby
# app/services/learning_engine.rb
class LearningEngine
  def learn_from_execution(task_session)
    feedback = analyze_execution(task_session)
    
    # Update template confidence scores
    if feedback.success?
      increase_template_confidence(task_session.workflow_template)
    else
      decrease_template_confidence(task_session.workflow_template)
      suggest_template_modifications(feedback)
    end
    
    # Extract reusable patterns
    patterns = extract_patterns(task_session)
    store_patterns(patterns)
  end
  
  def suggest_plan_improvements(workflow, context)
    similar_executions = find_similar_executions(workflow, context)
    successful_patterns = extract_successful_patterns(similar_executions)
    
    apply_patterns_to_workflow(workflow, successful_patterns)
  end
end
```

### Phase 5: Resource Management & Optimization (Week 5-6)

#### 5.1 Resource Manager

```ruby
# app/services/resource_manager.rb
class ResourceManager
  def initialize(entity)
    @entity = entity
    @budgets = load_budgets(entity)
  end
  
  def request_resources(agent_id, resource_type, amount)
    budget = @budgets[resource_type]
    
    if budget.can_afford?(amount)
      budget.consume(amount)
      grant_resources(agent_id, resource_type, amount)
    else
      suggest_alternatives(agent_id, resource_type, amount)
    end
  end
  
  def optimize_execution_plan(workflow)
    # Analyze cost vs speed tradeoffs
    parallel_cost = estimate_parallel_cost(workflow)
    sequential_cost = estimate_sequential_cost(workflow)
    
    if @budgets.prefer_speed? && can_afford_parallel?(parallel_cost)
      parallelize_workflow(workflow)
    else
      optimize_for_cost(workflow)
    end
  end
end
```

#### 5.2 Cost Tracking

```ruby
class CostTracker
  COSTS = {
    'gpt-4' => { per_1k_tokens: 0.03 },
    'claude-3-opus' => { per_1k_tokens: 0.015 },
    'dall-e-3' => { per_image: 0.04 }
  }
  
  def track_usage(service, usage_data)
    cost = calculate_cost(service, usage_data)
    
    ResourceUsage.create!(
      task_session_id: @task_session.id,
      service: service,
      usage: usage_data,
      cost: cost,
      timestamp: Time.current
    )
    
    check_budget_alerts(service, cost)
  end
end
```

### Phase 6: Production Readiness (Week 6-7)

#### 6.1 Error Recovery & Resilience

```ruby
# app/services/resilience/circuit_breaker.rb
class CircuitBreaker
  def call(service_name, &block)
    if open?(service_name)
      handle_open_circuit(service_name)
    else
      begin
        result = block.call
        record_success(service_name)
        result
      rescue => e
        record_failure(service_name)
        handle_failure(e, service_name)
      end
    end
  end
end
```

#### 6.2 Advanced Monitoring

```ruby
class ObservabilityServiceV2 < ObservabilityService
  def track_agent_decision(agent_id, decision, reasoning, confidence)
    track_event('agent.decision', {
      agent_id: agent_id,
      decision: decision,
      reasoning: reasoning,
      confidence: confidence,
      timestamp: Time.current
    })
  end
  
  def track_collaboration(agent_ids, collaboration_type, outcome)
    track_event('agents.collaboration', {
      agent_ids: agent_ids,
      type: collaboration_type,
      outcome: outcome,
      duration_ms: calculate_duration
    })
  end
end
```

#### 6.3 External Integration

```ruby
# app/services/webhook_orchestrator.rb
class WebhookOrchestrator
  def register_workflow_hooks(workflow_id, config)
    WebhookSubscription.create!(
      workflow_id: workflow_id,
      events: config[:events],
      url: config[:callback_url],
      headers: config[:headers]
    )
  end
  
  def pause_for_external_event(workflow_id, event_type, timeout)
    PausedWorkflow.create!(
      workflow_id: workflow_id,
      waiting_for: event_type,
      timeout_at: timeout.from_now
    )
  end
end
```

---

## 🚀 Migration Strategy

### Step 1: Parallel Development
- Build new components alongside existing ones
- Use feature flags to gradually enable new features
- Maintain backward compatibility

### Step 2: Incremental Rollout
1. Start with internal testing on non-critical workflows
2. A/B test new engine on 10% of workflows
3. Monitor performance and gradually increase
4. Full rollout once metrics improve

### Step 3: Data Migration
```ruby
class MigrateToV2Agents < ActiveRecord::Migration[7.0]
  def up
    # Create new tables
    create_table :agent_memories do |t|
      t.references :agent, type: :string
      t.jsonb :short_term_memory
      t.jsonb :long_term_memory
      t.timestamps
    end
    
    create_table :agent_collaborations do |t|
      t.references :task_session
      t.string :agent_ids, array: true
      t.string :collaboration_type
      t.jsonb :messages
      t.jsonb :outcome
      t.timestamps
    end
    
    # Migrate existing data
    TaskSession.find_each do |session|
      MigrateTaskSessionToV2.perform_async(session.id)
    end
  end
end
```

---

## 📊 Success Metrics

### Technical Metrics
- **Workflow Completion Rate**: Target 95% (current ~80%)
- **Average Execution Time**: Reduce by 40% via parallelization
- **Error Recovery Rate**: 90% automated recovery
- **Cost per Workflow**: Reduce by 30% via optimization

### Business Metrics
- **User Satisfaction**: Increase NPS by 20 points
- **Time to Value**: Reduce from hours to minutes
- **Platform Adoption**: 2x increase in daily active workflows

### Agent Performance
- **Decision Accuracy**: 90%+ correct first-time decisions
- **Collaboration Efficiency**: 50% reduction in steps via agent cooperation
- **Learning Effectiveness**: 25% improvement in plans over time

---

## 🛠️ Technical Requirements

### Infrastructure
- **Redis**: For blackboard and agent communication
- **PostgreSQL**: Enhanced with TimescaleDB for metrics
- **Sidekiq Pro**: For reliable background job processing
- **ElasticSearch**: For agent memory and pattern matching

### Monitoring
- **OpenTelemetry**: Full distributed tracing
- **Grafana**: Real-time dashboards
- **PagerDuty**: Alerting and escalation

### Security
- **Agent Sandboxing**: Isolated execution environments
- **Data Encryption**: At rest and in transit
- **Audit Logging**: Complete agent decision trail

---

## 🗓️ Timeline

### Month 1: Foundation
- Week 1-2: Agent Framework
- Week 3-4: Workflow Engine V2

### Month 2: Intelligence
- Week 1-2: Context & Collaboration
- Week 3-4: Learning Engine

### Month 3: Production
- Week 1-2: Resource Management
- Week 3-4: Testing & Rollout

---

## 🎯 Next Immediate Steps

1. **Create Agent Framework Package**
   ```bash
   rails generate package agents
   mkdir -p app/services/agents/{base,specialized,communication}
   ```

2. **Implement BaseAgent Class**
   - Start with simplified version
   - Add memory and context gradually

3. **Enhance PlannerAgentService**
   - Refactor to inherit from BaseAgent
   - Add learning capabilities

4. **Create Parallel Workflow Proof of Concept**
   - Pick simple workflow (data aggregation)
   - Implement parallel execution
   - Measure performance improvement

5. **Set Up Agent Communication**
   - Redis pub/sub for real-time
   - Database for persistence

This plan provides a clear path from the current system to a production-ready, nimble multi-agent system that can handle complex real-world scenarios with resilience and intelligence.

