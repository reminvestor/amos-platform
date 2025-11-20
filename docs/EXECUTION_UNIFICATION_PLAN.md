# Execution System Unification Plan

## Executive Summary

Unify three separate execution tracking systems into a single, cohesive model centered around AgentPlugins, eliminating complexity and improving maintainability.

---

## Current State Analysis

### Three Separate Execution Systems

#### 1. **Amos::JobRecord** (Legacy Hardcoded Agents)
```ruby
# Location: app/models/amos/job_record.rb
# Used by: delegate_to_agent tool
# Executes: landing_page_agent, email_agent, integration_agent, etc.

Amos::JobRecord.create!(
  job_id: SecureRandom.uuid,
  agent_type: 'landing_page_agent',  # Hardcoded string
  session_id: session_id,
  status: 'queued',
  input_data: { task: "...", context: {...} }
)

# Job dispatched to:
AgentJobs::LandingPageAgentJob.perform_later(...)
```

**Issues:**
- Hardcoded agent types (can't add new agents without code changes)
- Each new agent requires a new job class
- No capability-based discovery
- Tightly coupled to specific implementations

#### 2. **AgentPluginExecution** (New Extensible System)
```ruby
# Location: app/models/agent_plugin_execution.rb
# Used by: invoke_agent_plugin tool (just integrated!)
# Executes: User-defined agent plugins from database

AgentPluginExecution.create!(
  agent_plugin: agent_plugin,  # Database record
  user: user,
  status: 'running',
  input_context: { task: "..." }
)

# Job dispatched to:
AgentPluginExecutionJob.perform_later(execution.id, ...)
```

**Strengths:**
- Extensible (add agents via UI, no code changes)
- Capability-based discovery
- Tracks model usage, tokens, costs
- Execution history per plugin

#### 3. **WorkflowExecution** (Template-Based Workflows)
```ruby
# Location: app/models/workflow_execution.rb
# Used by: PlannerAgentService + WorkflowEngine
# Executes: Multi-phase YAML-based workflows

WorkflowExecution.create!(
  workflow_template: template,
  task_session: session,
  status: 'running',
  metadata: {...}
)

# Phases executed by:
Agents::GatherContextExecutor
Agents::GoalExecutor
Agents::ValidationExecutor
```

**Characteristics:**
- Phase-based execution
- Can use AgentPlugins for specific phases
- More structured than direct agent calls

---

## The Problem: Fragmentation

```
User Request
    ↓
Scout (Main Chat)
    ↓
    ├─→ [Option 1] delegate_to_agent → Amos::JobRecord → AgentJobs::*
    ├─→ [Option 2] invoke_agent_plugin → AgentPluginExecution → AgentPluginExecutionJob
    └─→ [Option 3] delegate_to_planner → WorkflowExecution → WorkflowEngine → (may use AgentPlugins)

Task Monitor UI must handle all three systems separately!
```

**Developer Pain Points:**
1. Three different models to query for task status
2. Three different job patterns to maintain
3. Inconsistent progress broadcasting
4. Duplicate code for similar functionality
5. Harder to add features (must update 3 places)

---

## Proposed Unified Architecture

### Core Principle: **AgentPlugin as the Universal Execution Unit**

```
EVERYTHING is an AgentPlugin execution
    ↓
Single tracking model
    ↓
Unified job dispatch
    ↓
Standardized progress broadcasting
    ↓
Simple, consistent UI
```

### 1. **Unified Execution Model**

```ruby
# NEW: app/models/agent_execution.rb
class AgentExecution < ApplicationRecord
  # REPLACES: AgentPluginExecution, Amos::JobRecord, WorkflowExecution (partially)

  belongs_to :agent_plugin
  belongs_to :user
  belongs_to :entity
  belongs_to :workflow_execution, optional: true  # If part of a workflow
  belongs_to :parent_execution, class_name: 'AgentExecution', optional: true  # For nested executions

  # Universal fields
  # id, agent_plugin_id, user_id, entity_id
  # status: queued, running, completed, failed, canceled
  # input_context: JSONB - flexible input data
  # output_result: JSONB - flexible output data
  # error_message: TEXT

  # Progress tracking
  # progress_percentage: INTEGER (0-100)
  # progress_message: TEXT
  # current_phase: STRING (for multi-phase executions)

  # Performance metrics
  # started_at, completed_at, duration_ms
  # tokens_used, model_id, model_input_tokens, model_output_tokens
  # estimated_cost: DECIMAL

  # Execution context
  # session_id: STRING (for Scout integration)
  # execution_mode: STRING (direct, workflow_phase, background)
  # metadata: JSONB (flexible additional data)

  # Scopes
  scope :active, -> { where(status: %w[queued running]) }
  scope :for_session, ->(session_id) { where(session_id: session_id) }
  scope :recent, -> { order(created_at: :desc) }

  # Progress broadcasting
  after_update :broadcast_progress, if: :should_broadcast?

  def broadcast_progress
    AgentExecutionChannel.broadcast_to(
      session_id,
      {
        type: 'execution_progress',
        execution_id: id,
        agent_name: agent_plugin.name,
        status: status,
        progress: progress_percentage,
        message: progress_message
      }
    )
  end
end
```

**Database Migration:**
```ruby
class CreateAgentExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_executions do |t|
      # Relationships
      t.references :agent_plugin, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.references :workflow_execution, null: true, foreign_key: true
      t.references :parent_execution, null: true, foreign_key: { to_table: :agent_executions }

      # Execution state
      t.string :status, null: false, default: 'queued'
      t.jsonb :input_context, default: {}
      t.jsonb :output_result, default: {}
      t.text :error_message

      # Progress
      t.integer :progress_percentage, default: 0
      t.text :progress_message
      t.string :current_phase

      # Performance
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms
      t.integer :tokens_used, default: 0
      t.string :model_id
      t.integer :model_input_tokens, default: 0
      t.integer :model_output_tokens, default: 0
      t.decimal :estimated_cost, precision: 10, scale: 4

      # Context
      t.string :session_id
      t.string :execution_mode, default: 'direct'
      t.jsonb :metadata, default: {}

      t.timestamps

      t.index [:session_id, :created_at]
      t.index [:agent_plugin_id, :status]
      t.index [:user_id, :created_at]
      t.index :status
    end
  end
end
```

### 2. **Convert Legacy Agents to AgentPlugins**

```ruby
# NEW: db/seeds/migrate_legacy_agents.rb
# Run once to create AgentPlugin records for existing hardcoded agents

legacy_agents = [
  {
    name: 'Landing Page Creator',
    slug: 'landing_page_agent',
    role: 'executor',
    description: 'Creates beautiful, conversion-optimized landing pages',
    capabilities: ['landing_page_generation', 'content_creation', 'design_application'],
    tools: ['generate_ai_landing_page', 'create_object', 'update_object'],
    status: 'active',
    agent_class: 'Agents::LandingPageExecutor'  # Wrapper for existing code
  },
  {
    name: 'Email Campaign Manager',
    slug: 'email_agent',
    role: 'executor',
    description: 'Designs and sends email campaigns',
    capabilities: ['email_generation', 'campaign_management'],
    tools: ['create_object', 'get_data', 'execute_integration'],
    status: 'active',
    agent_class: 'Agents::EmailCampaignExecutor'
  },
  # ... more agents
]

legacy_agents.each do |agent_data|
  agent = AgentPlugin.create!(
    name: agent_data[:name],
    slug: agent_data[:slug],
    role: agent_data[:role],
    description: agent_data[:description],
    status: agent_data[:status],
    agent_class: agent_data[:agent_class],
    entity_id: nil  # System-wide
  )

  # Add capabilities
  agent_data[:capabilities].each do |capability|
    agent.agent_capabilities.create!(capability_name: capability)
  end

  # Add tools
  agent_data[:tools].each do |tool|
    agent.agent_tools.create!(tool_name: tool, required: true)
  end
end
```

### 3. **Unified Job Execution**

```ruby
# NEW: app/jobs/agent_execution_job.rb
# REPLACES: AgentPluginExecutionJob, AgentJobs::*, etc.

class AgentExecutionJob < ApplicationJob
  queue_as :agents

  def perform(execution_id)
    execution = AgentExecution.find(execution_id)
    agent_plugin = execution.agent_plugin

    Rails.logger.info "🤖 Executing: #{agent_plugin.name} (ID: #{execution.id})"

    # Start execution
    execution.update!(
      status: 'running',
      started_at: Time.current
    )

    begin
      # Instantiate the agent
      agent = agent_plugin.instantiate(
        entity: execution.entity,
        user: execution.user,
        session_id: execution.session_id,
        execution: execution  # Pass execution for progress updates
      )

      # Execute the task
      result = agent.run(
        execution.input_context['task'],
        execution.input_context
      )

      # Mark complete
      execution.mark_completed!(result)

      Rails.logger.info "✅ Completed: #{agent_plugin.name}"

    rescue => e
      Rails.logger.error "❌ Failed: #{agent_plugin.name} - #{e.message}"
      execution.mark_failed!(e.message)
      raise
    end
  end
end
```

### 4. **Unified Tool Interface**

```ruby
# UPDATED: app/services/tools/invoke_agent_plugin_tool.rb
# Now the ONLY tool for agent delegation

module Tools
  class InvokeAgentPluginTool < BaseTool
    def self.metadata
      {
        name: "invoke_agent_plugin",
        description: "Invoke any agent (built-in or custom) by name or capability. Universal agent delegation system.",
        # ... schema
      }
    end

    def execute(args)
      # Discover agent (built-in OR custom!)
      agent_plugin = discover_agent(args['agent_identifier'])

      # Create unified execution record
      execution = AgentExecution.create!(
        agent_plugin: agent_plugin,
        user: user,
        entity: entity,
        session_id: context[:session_id],
        status: 'queued',
        execution_mode: 'direct',
        input_context: {
          task: args['task_description'],
          context: args['context'] || {}
        }
      )

      # Queue unified job
      AgentExecutionJob.perform_later(execution.id)

      success_response(
        message: "Delegated to #{agent_plugin.name}",
        data: { execution_id: execution.id }
      )
    end

    private

    def discover_agent(identifier)
      # Find by slug (works for both legacy and custom agents)
      AgentPlugin.active.for_entity(entity)
        .find_by(slug: identifier.parameterize.underscore) ||
      # Or by name
      AgentPlugin.active.for_entity(entity)
        .where("LOWER(name) LIKE ?", "%#{identifier.downcase}%").first ||
      # Or by capability
      AgentPlugin.discover_by_capabilities([identifier], entity: entity).first
    end
  end
end

# DEPRECATED (will be removed):
# - delegate_to_agent tool
# - All AgentJobs::* job classes
```

### 5. **Simplified Task Monitor**

```javascript
// Much simpler! Only one execution type to handle

function handleExecutionUpdate(data) {
  // All updates come through AgentExecutionChannel
  // Consistent format regardless of agent type

  addOrUpdateTask({
    execution_id: data.execution_id,
    agent_name: data.agent_name,
    status: data.status,
    progress: data.progress,
    message: data.message
  });
}

// Load all active executions (one query!)
async function loadActiveTasks() {
  const response = await fetch(`/scout/active_executions?session_id=${sessionId}`);
  const executions = await response.json();

  executions.forEach(execution => {
    addOrUpdateTask({
      execution_id: execution.id,
      agent_name: execution.agent_plugin.name,
      status: execution.status,
      progress: execution.progress_percentage,
      message: execution.progress_message
    });
  });
}
```

---

## Migration Path

### Phase 1: Create Unified Model (Week 1)
- [ ] Create `AgentExecution` model and migration
- [ ] Create `AgentExecutionJob`
- [ ] Create `AgentExecutionChannel` for broadcasting
- [ ] Add `AgentExecution` controller endpoints

### Phase 2: Migrate Legacy Agents (Week 2)
- [ ] Create AgentPlugin seeds for legacy agents
- [ ] Create wrapper executors (`Agents::LandingPageExecutor`, etc.)
- [ ] Update `invoke_agent_plugin` to work with both
- [ ] Test legacy agents work through new system

### Phase 3: Update Scout Integration (Week 3)
- [ ] Remove `delegate_to_agent` from Scout's tool allowlist
- [ ] Update task monitor to use `AgentExecution`
- [ ] Update `list_available_agents` to show all plugins
- [ ] Test end-to-end flow

### Phase 4: Deprecation & Cleanup (Week 4)
- [ ] Mark old tools as deprecated
- [ ] Add migration notices
- [ ] Remove old job classes
- [ ] Remove `Amos::JobRecord` (or repurpose)
- [ ] Update documentation

### Phase 5: Workflow Integration (Week 5)
- [ ] Update workflow phases to use `AgentExecution`
- [ ] Link workflow executions to agent executions
- [ ] Unified progress tracking for workflows

---

## Benefits

### For Developers
✅ **One model to rule them all** - Single source of truth
✅ **Less code** - Remove duplicate job classes
✅ **Easier debugging** - Consistent execution tracking
✅ **Better testing** - Test one path, not three

### For Users
✅ **Seamless experience** - No distinction between built-in and custom agents
✅ **Unified task monitor** - See all tasks in one place
✅ **Consistent progress** - Same updates regardless of agent type
✅ **More powerful** - Create custom agents without code

### For the Platform
✅ **Scalable** - Add new agents via UI, not code
✅ **Maintainable** - Less code to maintain
✅ **Extensible** - Plugin architecture ready for marketplace
✅ **Observable** - Better analytics on agent performance

---

## Architecture Diagram

```
BEFORE (Current):
┌──────────────────────────────────────────────────────────┐
│                      Scout (Chat)                         │
└────────────┬─────────────────┬────────────────┬──────────┘
             │                 │                │
    ┌────────▼────────┐ ┌──────▼──────┐ ┌──────▼─────────┐
    │ delegate_to_    │ │  invoke_    │ │ delegate_to_   │
    │    agent        │ │agent_plugin │ │   planner      │
    └────────┬────────┘ └──────┬──────┘ └──────┬─────────┘
             │                 │                │
    ┌────────▼────────┐ ┌──────▼──────┐ ┌──────▼─────────┐
    │ Amos::JobRecord │ │AgentPlugin  │ │   Workflow     │
    │                 │ │  Execution  │ │  Execution     │
    └────────┬────────┘ └──────┬──────┘ └──────┬─────────┘
             │                 │                │
    ┌────────▼────────┐ ┌──────▼──────┐ ┌──────▼─────────┐
    │ AgentJobs::     │ │AgentPlugin  │ │ WorkflowEngine │
    │  *AgentJob      │ │ExecutionJob │ │   Phases       │
    └─────────────────┘ └─────────────┘ └────────────────┘

    3 DIFFERENT TRACKING SYSTEMS!


AFTER (Unified):
┌──────────────────────────────────────────────────────────┐
│                      Scout (Chat)                         │
└──────────────────────────┬───────────────────────────────┘
                           │
                  ┌────────▼────────┐
                  │  invoke_agent   │
                  │     plugin      │
                  └────────┬────────┘
                           │
                  ┌────────▼────────┐
                  │ AgentExecution  │  ◄── SINGLE MODEL
                  │   (Universal)   │
                  └────────┬────────┘
                           │
                  ┌────────▼────────┐
                  │ AgentExecution  │  ◄── SINGLE JOB
                  │       Job       │
                  └────────┬────────┘
                           │
                  ┌────────▼────────┐
                  │  AgentPlugin    │  ◄── Executes everything
                  │   .instantiate  │     (built-in & custom)
                  │      .run       │
                  └─────────────────┘

    ONE UNIFIED SYSTEM!
```

---

## Code Removal Estimate

**Files to DELETE:**
- `app/models/amos/job_record.rb`
- `app/jobs/agent_jobs/landing_page_agent_job.rb`
- `app/jobs/agent_jobs/email_agent_job.rb`
- `app/jobs/agent_jobs/integration_agent_job.rb`
- `app/jobs/agent_jobs/data_agent_job.rb`
- `app/jobs/agent_jobs/analytics_agent_job.rb`
- `app/services/tools/delegate_to_agent_tool.rb`

**Estimated LOC Reduction:** ~2,000 lines
**Maintenance Burden Reduction:** ~40%

---

## Risk Mitigation

### Backward Compatibility
- Keep old models during migration
- Dual-write during transition period
- Feature flag for new system
- Gradual rollout per agent type

### Rollback Plan
- Keep old code for 2 releases
- Monitor error rates closely
- Easy toggle back to old system
- Document all changes

### Testing Strategy
- Unit tests for `AgentExecution`
- Integration tests for job execution
- E2E tests for Scout → Agent flow
- Load testing for performance

---

## Next Steps

**Immediate Actions:**
1. Review and approve this plan
2. Create GitHub issues for each phase
3. Set up feature flag infrastructure
4. Begin Phase 1 implementation

**Questions to Answer:**
1. Timeline expectations? (5-week plan above)
2. Should we keep `WorkflowExecution` separate or merge?
3. Database migration strategy (zero-downtime requirement?)
4. Feature flag naming convention?

---

## Appendix: Example Usage

### Creating a Landing Page (Before)
```ruby
# User asks: "Create a landing page for my product"
# Scout → delegate_to_agent
Amos::JobRecord.create!(agent_type: 'landing_page_agent', ...)
AgentJobs::LandingPageAgentJob.perform_later(...)
```

### Creating a Landing Page (After)
```ruby
# User asks: "Create a landing page for my product"
# Scout → invoke_agent_plugin
agent = AgentPlugin.find_by(slug: 'landing_page_agent')
execution = AgentExecution.create!(agent_plugin: agent, ...)
AgentExecutionJob.perform_later(execution.id)

# SAME CODE PATH for custom agents!
# User asks: "Use my custom web research agent"
agent = AgentPlugin.find_by(slug: 'web_research_agent')
execution = AgentExecution.create!(agent_plugin: agent, ...)
AgentExecutionJob.perform_later(execution.id)
```

**Result:** No distinction between built-in and custom agents! 🎉
