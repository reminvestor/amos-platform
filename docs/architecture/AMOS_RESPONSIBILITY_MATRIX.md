# AMOS Responsibility Matrix & Agent Collaboration Guide

## 🎯 Core Philosophy

**Amos is the orchestrator.** He doesn't do everything - he coordinates a team of specialists.

Think of Amos as a **senior project manager** who:
- Understands what needs to be done
- Knows who on the team can do it best
- Coordinates handoffs and tracks progress
- Steps in for simple tasks, delegates complex ones

---

## 📊 Responsibility Matrix

### ✅ AMOS HANDLES DIRECTLY

| Category | Examples | Why Amos? |
|----------|----------|-----------|
| **Data Queries** | "Show my campaigns", "How many contacts?" | Simple read operations - no specialist needed |
| **Canvas Loading** | "Show dashboard", "Open contact viewer" | UI navigation is Amos's domain |
| **Simple CRUD** | "Create a contact named John", "Delete campaign X" | Single, straightforward operations |
| **Memory/Context** | "What did we discuss?", "Remember that..." | Amos owns conversation memory |
| **Routing Questions** | "Who can help with X?", "What agents exist?" | Amos knows the team |
| **Status Checks** | "What's the agent working on?", "Task status?" | Amos monitors work items |
| **Answering Questions** | "How does X work?", "Explain..." | If Amos knows, he answers |

**Rule of thumb**: If it's a single operation with a known outcome → Amos does it.

---

### 🤝 AMOS DELEGATES TO AGENTS

| Category | Examples | Agent Type | Why Delegate? |
|----------|----------|------------|---------------|
| **Creative Content** | "Design a landing page", "Write email sequence" | Content Specialists | Requires iteration, creativity |
| **Multi-step Builds** | "Build a campaign flow", "Create module" | Architects | Complex, phased work |
| **Integration Operations** | "Sync QuickBooks", "Import Stripe customers" | Integration Experts | API-specific knowledge |
| **Module Data** | "Update all inventory records", "Fix module schema" | Module Agents | Schema expertise |
| **Research Tasks** | "Research competitors", "Analyze market" | Research Agents | Needs exploration |
| **Complex Repairs** | "Fix the broken workflow", "Debug integration" | Repair Specialists | Diagnostic expertise |

**Rule of thumb**: If it needs creativity, exploration, or deep domain expertise → Delegate.

---

## 🔄 Agent Collaboration Protocols

### Protocol 1: ASK (Quick Consultation)

**Use when**: Agent needs advice, review, or quick input - NOT a full task delegation.

```
┌─────────────────┐     ask_agent_for_help      ┌─────────────────┐
│  Agent A        │ ─────────────────────────▶  │   Agent B       │
│  (needs advice) │                              │   (expert)      │
└─────────────────┘                              └─────────────────┘
         │                                               │
         │   request_type: 'advice' | 'review'          │
         │   description: "Should I use X or Y?"         │
         │                                               │
         └──────────── receives response ◀──────────────┘
                   (synchronous - waits)
```

**Request Types**:
- `advice`: "How should I approach X?" (cost: 2 energy, reward: 5)
- `review`: "Does this look right?" (cost: 2 energy, reward: 5)
- `subtask`: "Handle this piece for me" (cost: 10 energy, reward: 15)
- `full_delegation`: "Take over this whole thing" (cost: 15 energy, reward: 25)

**Tracking**: `AgentCollaborationRequest` with timeout and depth limits (MAX_DEPTH = 4)

---

### Protocol 2: PROPOSE → ACCEPT/REJECT (Handshake)

**Use when**: Delegating a task that the receiving agent must evaluate first.

```
┌─────────────────┐    propose_task_to_agent    ┌─────────────────┐
│  Amos/Agent     │ ─────────────────────────▶  │   Agent B       │
│  (has task)     │                              │   (candidate)   │
└─────────────────┘                              └─────────────────┘
                                                         │
                              evaluate_capability()      │
                                                         ▼
                   ┌──────────────────────────────────────────────┐
                   │  Can I do this?                              │
                   │  - Check tools_needed vs my tools            │
                   │  - Check required_capabilities               │
                   │  - Check object_type support                 │
                   │  - Check domain match (fallback)             │
                   └──────────────────────────────────────────────┘
                                                         │
                          ┌──────────────────────────────┴───────┐
                          ▼                                      ▼
                   ACCEPTED (confidence %)              REJECTED (reason)
                   proposal_id returned                 alternatives suggested
```

**AgentTaskProposal** tracks:
- `status`: proposed → accepted/rejected → executing → completed/failed
- `confidence`: How sure the agent is (0-100%)
- `missing_tools`: What the agent lacks
- `suggested_alternatives`: Other agents who might help
- `task_succeeded`: Did it actually work? (for learning)

---

### Protocol 3: DELEGATE (Full Task Assignment)

**Use when**: Task is accepted, now execute it.

```
┌─────────────────┐     delegate_to_agent       ┌─────────────────┐
│  Amos           │ ─────────────────────────▶  │   Agent         │
│                 │    (with proposal_id OR     │                 │
│                 │     auto-handshake)         │                 │
└─────────────────┘                              └─────────────────┘
                                                         │
                                                         ▼
                                         ┌───────────────────────────┐
                                         │  AgentPluginExecution     │
                                         │  - status: running        │
                                         │  - tracks progress        │
                                         │  - captures output        │
                                         └───────────────────────────┘
                                                         │
         ┌───────────────────────────────────────────────┤
         ▼                                               ▼
  Agent may ASK USER                           Agent may ASK OTHER AGENTS
  (AgentInputRequest)                          (AgentCollaborationRequest)
         │                                               │
         ▼                                               ▼
  User answers via                             Other agent responds
  Hub or Question Queue                        (with depth tracking)
```

---

### Protocol 4: HANDOFF (Agent → Human)

**Use when**: Agent needs human decision, approval, or cannot proceed.

```
┌─────────────────┐     request_handoff         ┌─────────────────┐
│  Agent          │ ─────────────────────────▶  │   Human         │
│  (blocked)      │                              │   (decision)    │
└─────────────────┘                              └─────────────────┘
                           │
                           ▼
              ┌──────────────────────────┐
              │  HubMessage              │
              │  - type: HANDOFF_REQUEST │
              │  - completed_items: [...]│
              │  - needed_items: [...]   │
              │  - next_steps: [...]     │
              │  - needs_response: true  │
              └──────────────────────────┘
                           │
         ┌─────────────────┴─────────────────┐
         ▼                                   ▼
  Human ACCEPTS                       Human REJECTS
  (provides response)                 (provides reason)
         │                                   │
         ▼                                   ▼
  Agent RESUMES                       Agent STOPS
  (continues work)                    (creates work item)
```

---

## 🛡️ Nothing Gets Dropped: Tracking & Accountability

### 1. Execution Tracking

Every delegated task creates an `AgentPluginExecution`:

```ruby
AgentPluginExecution
├── status: pending → running → completed/failed/waiting_for_input
├── started_at, completed_at (duration tracking)
├── input_context (what was requested)
├── output_result (what was produced)
├── tokens_used, model_id (resource tracking)
└── agent_work_item (human-visible work item)
```

### 2. Work Items (User Visibility)

When agents complete work, they create `AgentWorkItem`:

```ruby
AgentWorkItem
├── work_type: task_completed | needs_review | error | handoff
├── title, description (human-readable summary)
├── priority: low | normal | high | urgent
├── status: pending → acknowledged → completed
└── result_summary, artifacts (deliverables)
```

**Canvas**: Users see these in the "Work Items" canvas.

### 3. Stuck Task Detection

`ScheduledTaskRun` has built-in stuck detection:

```ruby
STUCK_RUNNING_THRESHOLD = 10.minutes
STUCK_PENDING_THRESHOLD = 5.minutes

# Auto-cleanup:
ScheduledTaskRun.cleanup_stuck_runs!
```

### 4. Question Queue

When agents need input:

```ruby
AgentInputRequest
├── question: What they're asking
├── variable_name: Where answer goes
├── status: pending → answered → expired
├── priority: 1-10 (5 = normal)
├── expires_at: Auto-timeout
└── session_id: For live broadcasts
```

**UI**: Appears in `/scout/questions` and Hub notifications.

---

## 🔄 Complete Flow Example

**User Request**: "Design a landing page for my new product launch"

```
1. USER → AMOS
   "Design a landing page for my new product launch"
   
2. AMOS: Preprocessor runs in parallel
   - Canvas: :keep_current (no auto-load needed)
   - Tools: [delegate_to_agent, find_best_agent, ...]
   - Agents: [landing_page_manager] ← delegate_first: true
   - Context Inject: "⚡ [DELEGATE TO: Landing Page Manager]"

3. AMOS: Recognizes this is creative work → delegates
   delegate_to_agent(
     agent_type: "landing_page_manager",
     task_description: "Design a landing page for product launch"
   )
   
4. DELEGATE: Auto-handshake evaluates
   AgentTaskProposal created → evaluate_capability()
   → domain_match: landing_page ✓
   → confidence: 85%
   → ACCEPTED

5. EXECUTION: Agent starts working
   AgentPluginExecution created (status: running)
   Agent uses: generate_ai_landing_page, analyze_screenshot_for_design

6. AGENT → USER: Needs input
   ask_user("What's the product name and key benefits?")
   AgentInputRequest created → broadcast to user

7. USER → AGENT: Provides answer
   "It's TechWidget Pro - saves 50% time on X"
   AgentInputRequest.answer!() → agent resumes

8. AGENT: May consult another agent
   ask_agent_for_help(
     request_type: "advice",
     helper_agent_slug: "brand_specialist",
     description: "What color palette for tech product?"
   )
   AgentCollaborationRequest created → helper responds

9. AGENT: Completes work
   Creates landing page, updates execution
   AgentPluginExecution.complete!(output: { landing_page_id: 123 })

10. WORK ITEM: Created for user
    AgentWorkItem.create!(
      work_type: "task_completed",
      title: "Landing page ready: TechWidget Pro",
      artifacts: { landing_page_id: 123 }
    )

11. AMOS: Notified of completion
    ScoutChannel.broadcast → "Landing page is ready! View it in your Work Items."
```

---

## 🔧 Improvements to Make Tighter

### Current Gaps

1. **No periodic check for stale executions** - add a cron job
2. **Collaboration depth limit could be bypassed** - strengthen validation
3. **Energy system is optional** - consider making mandatory for production
4. **Hub thread creation is inconsistent** - standardize thread creation

### Recommended Actions

```ruby
# 1. Add periodic stale execution checker
# lib/tasks/agent_health.rake
namespace :agents do
  task check_stale: :environment do
    stale = AgentPluginExecution.running
      .where('started_at < ?', 30.minutes.ago)
    
    stale.each do |exec|
      exec.mark_failed!("Execution timed out")
      # Create work item for user
    end
  end
end

# 2. Ensure all delegations go through Hub
# In delegate_to_agent_tool.rb, always create thread:
Hub::BridgeService.new(entity: entity)
  .handle_execution_started(execution)

# 3. Add completion callbacks
# In AgentPluginExecution model:
after_update :notify_completion, if: :just_completed?
```

---

## 📐 Decision Tree for Amos

```
USER REQUEST
     │
     ▼
Is it a question/show request?
     │
     ├── YES → Handle directly (get_data, load_canvas)
     │
     └── NO → Is it a single, simple operation?
              │
              ├── YES → Handle directly (create_object, etc.)
              │
              └── NO → Does it need creativity/expertise?
                       │
                       ├── YES → Find agent → Delegate
                       │         (with handshake if new agent)
                       │
                       └── NO → Does it involve integrations?
                                │
                                ├── YES → Delegate to integration agent
                                │
                                └── NO → Handle with tools
                                         (but be ready to delegate if complex)
```

---

## 📊 Metrics to Track

| Metric | Good | Warning | Critical |
|--------|------|---------|----------|
| Task completion rate | >90% | 70-90% | <70% |
| Avg execution time | <5min | 5-15min | >15min |
| Handshake rejection rate | <20% | 20-40% | >40% |
| User question timeout rate | <5% | 5-15% | >15% |
| Stuck execution count | 0 | 1-3 | >3 |

---

*Last updated: January 2026*

