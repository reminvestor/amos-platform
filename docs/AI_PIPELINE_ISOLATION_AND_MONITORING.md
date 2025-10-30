# AI Pipeline Isolation and Monitoring Architecture

Complete guide to how entity isolation, async processing, monitoring, and timeout handling work in the AI Development Pipeline.

---

## 🔐 Entity Isolation (Multi-Tenancy)

Each entity's pipeline executions are completely isolated from other entities.

### Database-Level Isolation

**All pipeline tables have `entity_id` foreign key**:

```ruby
# All queries automatically scoped by entity
current_entity.pipeline_executions
# => SELECT * FROM pipeline_executions WHERE entity_id = 123

current_entity.mcp_connections
# => SELECT * FROM mcp_connections WHERE entity_id = 123
```

**Controller Scoping**:

```ruby
# app/controllers/admin/pipeline_executions_controller.rb
def index
  @pipeline_executions = current_entity.pipeline_executions  # Auto-scoped!
                                      .includes(:mcp_connection, :agent_executions)
                                      .order(created_at: :desc)
end
```

**Model Associations**:

```ruby
class PipelineExecution < ApplicationRecord
  belongs_to :entity  # Required - can't create without entity_id

  validates :ticket_id, uniqueness: { 
    scope: [:entity_id, :mcp_connection_id] 
  }
end
```

### Workspace Isolation

**Each agent execution gets its own isolated filesystem workspace**:

```bash
/tmp/pipeline-{execution_id}/
  ├── clarifier/     # 0700 permissions (owner-only)
  ├── planner/       # 0700 permissions
  ├── coder/         # 0700 permissions, git clone here
  └── reviewer/      # 0700 permissions
```

**Security Features**:
- **0700 permissions** - Only the process owner can access
- **Separate directories** per execution - No file conflicts between entities
- **Automatic cleanup** - CleanupWorkspacesJob removes old workspaces after 24 hours
- **Path validation** - Prevents directory traversal attacks

### Credential Isolation

**Each entity has their own encrypted credentials**:

```ruby
# app/models/mcp_connection.rb
class McpConnection < ApplicationRecord
  belongs_to :entity
  encrypts :config  # AWS credentials, API tokens encrypted per-entity
end

# Entity A's JIRA credentials ≠ Entity B's JIRA credentials
entity_a.mcp_connections.find_by(system_type: 'jira')
# => { url: 'https://companyA.atlassian.net', api_token: 'encrypted-A' }

entity_b.mcp_connections.find_by(system_type: 'jira')
# => { url: 'https://companyB.atlassian.net', api_token: 'encrypted-B' }
```

---

## ⚡ Async Processing Architecture

The pipeline uses **SolidQueue** (not Sidekiq) for background job processing.

### Queue Structure

**3 priority queues** defined in `config/queue.yml`:

```yaml
queues:
  pipeline:       # Priority 10 (highest)
    threads: 3
    max_concurrent: 5
  agents:         # Priority 8
    threads: 5
    max_concurrent: 10
  maintenance:    # Priority 2 (lowest)
    threads: 1
```

### Job Flow (Per Entity)

```
User creates ticket in JIRA with status "Ready for Dev"
  ↓
TicketWatcherJob runs every 5 minutes (queue: pipeline)
  ↓
Detects new ticket → Creates PipelineExecution (entity_id: 123, status: new)
  ↓
ProcessPipelineJob.perform_later(pipeline.id) (queue: pipeline)
  ↓
Orchestrator transitions to CLARIFYING
  ↓
AgentExecutionJob.perform_later(agent_execution.id) (queue: agents)
  ↓
ClarifierAgent analyzes ticket (Claude 3.5 Haiku API call)
  ↓
ProcessPipelineJob.set(wait: 5.seconds).perform_later(pipeline.id)
  ↓
Orchestrator sees CLARIFYING complete → transitions to PLANNING
  ↓
AgentExecutionJob.perform_later (PlannerAgent)
  ↓
... continues through all states
```

### Concurrency Control

**Resource Limits** (per application, across all entities):

```yaml
max_concurrent_pipelines: 5       # Max 5 pipeline orchestrations running
max_concurrent_agents: 10         # Max 10 AI agents executing
max_tokens_per_hour: 1000000      # 1M tokens per hour limit
daily_ai_cost_limit: 1000         # $1000 daily spend limit
```

**Why Limits?**
- Prevents runaway AI costs
- Ensures fair resource sharing across entities
- Protects external APIs from rate limiting

**What Happens When Limit Reached?**
- New jobs queue (not rejected!)
- Jobs execute when concurrency slot opens
- Graceful degradation vs hard failures

### State Machine Progression

**14 states with automatic transitions**:

```
NEW → CLARIFYING → PLANNING → IMPLEMENTING → REVIEW → TESTING →
DEV → STAGING → AWAITING_PROD_APPROVAL → PROD → DONE

                                 ↓
                        FAILED / ROLLED_BACK / BLOCKED
```

**Each transition**:
1. Validates allowed (StateMachine.can_transition?)
2. Updates `status` and `state_changed_at`
3. Creates audit event in `pipeline_events` table
4. Schedules next ProcessPipelineJob in 5 seconds
5. Sends notification (Slack/Email if configured)

**Self-Scheduling Pattern**:

```ruby
# Orchestrator schedules itself to check progress
def schedule_next_step
  ProcessPipelineJob.set(wait: 5.seconds).perform_later(pipeline_execution.id)
end
```

This creates a **polling loop** that runs until terminal state (done/failed/rolled_back).

---

## 📊 Monitoring Dashboard

Admin UI provides real-time visibility into pipeline executions.

### Dashboard View

**URL**: `/admin/pipeline/executions`

**Features**:
- **6 stat cards**: Total, Active, Completed, Failed, Total Cost, Total Tokens
- **Filters**: Status, Priority, Ticket System
- **Table view**: All executions with status badges, duration, cost
- **Actions**: View, Retry (failed), Cancel (active)
- **Pagination**: 20 per page (Kaminari)

**Screenshot**:

```
┌─────────────────────────────────────────────────────────────┐
│ Total Pipelines │ Active Now │ Completed │ Failed │ Cost   │
│       247       │     12     │    203    │   32   │ $285.42│
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Ticket ID │ Title         │ Status  │ Duration │ Cost      │
│─────────────────────────────────────────────────────────────│
│ PROJ-456  │ Add user auth │ REVIEW  │ 23m 14s  │ $0.92  ✓ │
│ PROJ-455  │ Fix bug #123  │ DONE    │ 42m 08s  │ $1.16  ✓ │
│ PROJ-454  │ Update logo   │ FAILED  │ 12m 31s  │ $0.15  ↻ │
└─────────────────────────────────────────────────────────────┘
```

### Detail View

**URL**: `/admin/pipeline/executions/:id`

**Sections**:
1. **Overview** - Ticket info, PR link, branch, cost, duration
2. **Agent Timeline** - Visual timeline of all agent executions with status
3. **Artifacts** (left panel) - Generated files (plans, reports, code)
4. **Events Audit Trail** (right panel) - All state transitions and system events
5. **Human Interactions** - Clarification questions and approval requests

**Agent Timeline Example**:

```
● ClarifierAgent     ✅ Completed  |  $0.02  |  2m 14s
│
● PlannerAgent       ✅ Completed  |  $0.15  |  4m 32s
│
● CoderAgent         ✅ Completed  |  $0.75  |  18m 47s
│
● ReviewerAgent      🔄 Running... |  -      |  3m 12s (so far)
```

**Events Audit Trail Example**:

```
ticket.intake              | system | 10:23:14 AM
ticket.clarified           | agent  | 10:25:28 AM
plan.ready                 | agent  | 10:30:00 AM
pr.opened                  | agent  | 10:48:47 AM
pr.needs_changes           | agent  | 10:52:19 AM
state.transition.review_to_implementing | system | 10:52:20 AM
```

---

## ⏱️ Timeout Detection and Handling

**3-layer timeout system** to prevent stuck pipelines:

### 1. Pipeline-Level Timeouts

**Method**: `PipelineExecution#stuck?`

**Timeout thresholds by state**:

```ruby
State                  | Timeout | Reason
-----------------------|---------|---------------------------
clarifying, planning   | 15 min  | AI analysis should be fast
implementing           | 30 min  | Code generation can be slow
review                 | 10 min  | Quick security scan
testing, dev, staging  | 20 min  | Deployment and tests
awaiting_prod_approval | 4 hours | Human approval window
blocked                | 2 hours | Human clarification window
```

**How it works**:

```ruby
def stuck?
  return false if terminal_state?
  return false unless state_changed_at || started_at

  last_activity = state_changed_at || started_at
  timeout_threshold = stuck_timeout_for_state(status)

  last_activity < timeout_threshold.ago  # True if stuck!
end
```

**Example**:
- Pipeline enters IMPLEMENTING at 10:00 AM
- Timeout threshold = 30 minutes
- Current time = 10:35 AM
- `10:00 AM < 30.minutes.ago` = true → **STUCK!**

### 2. Agent-Level Timeouts

**Method**: `PipelineExecution#agent_stuck?`

**Detects agents running > 15 minutes without completing**:

```ruby
def agent_stuck?
  agent = running_agent_execution
  return false unless agent

  # Agent created_at < 15 minutes ago?
  agent.created_at < 15.minutes.ago
end
```

**What gets checked**:
- Agent status is `running` or `pending`
- Agent was created > 15 minutes ago
- Agent hasn't completed or failed

### 3. Interaction Timeouts

**Method**: `PipelineInteraction#timeout_at`

**Timeouts for human responses**:

```ruby
# Clarification questions: 2 hour timeout
interaction = pipeline.pipeline_interactions.create!(
  interaction_type: 'clarification',
  question: 'Should we support OAuth or email/password auth?',
  timeout_at: 2.hours.from_now  # Deadline!
)

# Production approval: 4 hour timeout
interaction = pipeline.pipeline_interactions.create!(
  interaction_type: 'approval',
  question: 'Approve deployment to production?',
  timeout_at: 4.hours.from_now
)
```

### Timeout Monitor Job

**File**: `app/jobs/pipeline_timeout_monitor_job.rb`

**Runs**: Every 5 minutes (configured in `config/recurring.yml`)

**What it does**:

```ruby
Entity.find_each do |entity|
  active_pipelines = entity.pipeline_executions.active

  active_pipelines.each do |pipeline|
    # Check 1: Pipeline stuck?
    if pipeline.stuck?
      pipeline.cancel_stuck!("Stuck in #{pipeline.status} for > #{timeout} min")
      notify_admins(pipeline, reason)
    end

    # Check 2: Agent stuck?
    if pipeline.agent_stuck?
      agent = pipeline.running_agent_execution
      agent.update!(status: :failed, error_message: "Timeout")
      pipeline.cancel_stuck!("Agent #{agent.agent_id} stuck")
      notify_admins(pipeline, reason)
    end

    # Check 3: Human interaction timeout?
    timed_out = pipeline.pipeline_interactions
                        .where(status: :pending)
                        .where('timeout_at < ?', Time.current)

    if timed_out.any?
      timed_out.each { |i| i.update!(status: :timeout) }
      pipeline.cancel_stuck!("Interaction timeout")
      notify_admins(pipeline, reason)
    end
  end
end
```

**Actions taken on timeout**:
1. Logs warning to Rails logger
2. Creates `execution.timeout` event in audit trail
3. Marks pipeline as **FAILED** with reason
4. Sends notification to admins (Slack + Email if configured)

### Manual Cancellation

**Admins can also manually cancel stuck pipelines via UI**:

```
[Admin Dashboard] → [View Pipeline] → [Cancel Pipeline] button
  ↓
POST /admin/pipeline/executions/:id/cancel
  ↓
pipeline_execution.update!(status: :failed, completed_at: Time.current)
  ↓
Creates event: execution.cancelled (source: admin)
```

---

## 🔔 Notification Channels

Notifications sent when pipelines transition states or timeout.

### Slack Notifications

**Channels**:
- `#ai-pipeline-status` - State changes (clarifying → planning → implementing)
- `#ai-clarifications` - Questions for humans (ClarifierAgent)
- `#ai-pipeline-approvals` - Production deployment requests
- `#ai-pipeline-alerts` - Failures and timeouts

**Message Format** (Block Kit):

```
🤖 AI Pipeline Update: PROJ-456

Add user authentication feature

Status: IMPLEMENTING → REVIEW
Agent: CoderAgent completed in 18m 47s
PR: https://github.com/org/repo/pull/789

Cost: $0.75 | Tokens: 10,234

[View in Admin UI] [View Ticket]
```

**Threaded Conversations**:
- All updates for a pipeline go in same thread
- `pipeline_execution.slack_thread_ts` stores thread ID
- Keeps Slack channels organized

### Email Notifications

**Recipients**:
- **Clarifications** → Ticket assignee
- **Approvals** → Release managers (configured in ENV)
- **Failures** → On-call team
- **Timeouts** → Admins

**Template**: HTML with plain text fallback

**Links**:
- View in Admin UI: `/admin/pipeline/executions/:id`
- View Ticket: JIRA/Azure DevOps URL
- View PR: GitHub/Azure Repos URL

---

## 🔄 How Entity Pipelines Run (End-to-End)

### Scenario: 3 Entities, 5 Concurrent Tickets

**Entities**:
- Entity A (Acme Corp) - 2 tickets
- Entity B (Beta Inc) - 2 tickets
- Entity C (Gamma LLC) - 1 ticket

**Time**: 10:00 AM

### Step 1: Ticket Detection (10:00 AM)

```
TicketWatcherJob runs (every 5 minutes)
  ↓
Queries each entity's MCP connections:
  - Entity A → JIRA connection → Finds 2 new tickets
  - Entity B → Azure DevOps connection → Finds 2 new tickets
  - Entity C → JIRA connection → Finds 1 new ticket
  ↓
Creates 5 PipelineExecutions:
  - pipeline_123 (entity_id: A, ticket: ACME-101)
  - pipeline_124 (entity_id: A, ticket: ACME-102)
  - pipeline_125 (entity_id: B, ticket: BETA-501)
  - pipeline_126 (entity_id: B, ticket: BETA-502)
  - pipeline_127 (entity_id: C, ticket: GAMMA-999)
```

### Step 2: Initial Orchestration (10:00:05 AM)

```
5 ProcessPipelineJobs queued (queue: pipeline, priority 10)

Concurrency limit: 5 pipelines max
All 5 jobs start immediately:
  ↓
5 Orchestrators initialize
  ↓
All transition: NEW → CLARIFYING
  ↓
5 AgentExecutionJobs queued (queue: agents, priority 8)
```

### Step 3: Agent Execution (10:00:10 AM)

```
Concurrency limit: 10 agents max
All 5 ClarifierAgent jobs start immediately:

Agent Execution #1 (pipeline_123, Entity A):
  ↓ Workspace: /tmp/pipeline-123/clarifier (0700)
  ↓ Claude API call: "Analyze ACME-101 ticket..."
  ↓ Cost: $0.02, Tokens: 2000
  ↓ Output: { needs_clarification: false }
  ↓ Duration: 2m 14s
  ↓ Status: COMPLETED

Agent Execution #2 (pipeline_124, Entity A):
  ↓ Same as above, different workspace
  ↓ Output: { needs_clarification: true, questions: [...] }
  ↓ → Creates PipelineInteraction (timeout: 2 hours)
  ↓ → Transitions to BLOCKED (waits for human)

Agent Execution #3-5 (Entities B, C):
  ↓ All run in parallel, separate workspaces
  ↓ Entity B uses their own AWS credentials
  ↓ Entity C uses their own AWS credentials
```

### Step 4: State Progression (10:05 AM)

```
Pipeline 123 (Entity A): CLARIFYING → PLANNING
  ↓ ProcessPipelineJob scheduled (5 seconds later)
  ↓ PlannerAgent queued

Pipeline 124 (Entity A): CLARIFYING → BLOCKED
  ↓ ProcessPipelineJob sees blocked state
  ↓ Checks for pending interactions
  ↓ Waits for human response (no further action)
  ↓ Slack message sent to #ai-clarifications
  ↓ Email sent to ticket assignee

Pipelines 125, 126, 127: All proceed to PLANNING
```

### Step 5: Parallel Execution Continues

```
10:10 AM: 4 PlannerAgents running (pipeline 124 still blocked)
10:15 AM: Planning complete, transitions to IMPLEMENTING
10:20 AM: CoderAgent starts generating code
10:38 AM: PRs created on GitHub (4 pipelines)
10:40 AM: ReviewerAgent starts code review
10:45 AM: Tests run, deploy to dev
11:00 AM: 3 pipelines reach DONE, 1 reaches FAILED

Entity A's pipeline 124 still blocked waiting for human
```

### Step 6: Timeout Detection (11:00 AM - 2 hours later)

```
PipelineTimeoutMonitorJob runs (every 5 minutes)
  ↓
Checks pipeline 124 (Entity A):
  - Status: BLOCKED
  - Last activity: 10:02 AM
  - Timeout threshold: 2 hours
  - Current time: 12:02 PM (2 hours 0 minutes)
  ↓
Pipeline 124 stuck? YES!
  ↓
cancel_stuck!("Human interaction timeout (clarification)")
  ↓
Status: BLOCKED → FAILED
  ↓
Event created: execution.timeout
  ↓
Slack alert sent to #ai-pipeline-alerts
  ↓
Email sent to admins
```

### Key Observations

**Entity Isolation**:
- ✅ Each entity's pipelines use their own credentials
- ✅ Separate workspaces prevent file conflicts
- ✅ Database queries scoped to `current_entity`

**Async Processing**:
- ✅ 5 pipelines orchestrated concurrently
- ✅ Up to 10 agents running in parallel
- ✅ Self-scheduling pattern (polls every 5 seconds)
- ✅ Jobs queue when limits reached (graceful degradation)

**Monitoring**:
- ✅ Real-time dashboard shows all active pipelines
- ✅ Detailed view shows agent timeline, events, artifacts
- ✅ Manual cancel available for admins

**Timeout Handling**:
- ✅ Automatic detection every 5 minutes
- ✅ Different timeouts per state (15m AI, 4h human)
- ✅ Notifications sent on timeout
- ✅ Pipeline marked as failed with reason in audit trail

---

## 🎯 Summary

**Entity Isolation**: ✅ Multi-tenant at database, workspace, and credential levels

**Async Processing**: ✅ SolidQueue with 3 priority queues, concurrency limits, self-scheduling

**Monitoring**: ✅ Real-time dashboard with stats, filters, detail views, agent timelines

**Timeout Handling**: ✅ 3-layer detection (pipeline, agent, interaction) with automatic cancellation

**Admin Controls**: ✅ Manual cancel, retry, view artifacts, respond to interactions

**Cost Tracking**: ✅ Per-pipeline tokens and cost, aggregated stats, budget alerts

---

**Access the Dashboard**: `/admin/pipeline/executions`

**Run Timeout Monitor Manually**: `PipelineTimeoutMonitorJob.perform_now`

**Check Stuck Pipelines**: `PipelineExecution.active.select(&:stuck?)`
