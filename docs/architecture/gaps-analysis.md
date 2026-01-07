# AMOS Integration Gaps Analysis

> Systems that exist but aren't fully connected

---

## 🔴 Critical Gaps (High Priority)

### 1. AMOS Orchestrator ↔ ScoutGenericToolsServiceV2

**Current State:**
- `Amos::Orchestrator` exists with full capabilities
- `ScoutGenericToolsServiceV2` is the actual service processing user messages
- **They don't talk to each other**

**Gap:**
```ruby
# Current: ScoutGenericToolsServiceV2 builds its own prompt
system_prompt = build_system_prompt(current_canvas)

# Should be: Use Orchestrator
orchestrator = Amos::Orchestrator.new(entity: @entity, user: @user)
system_prompt = orchestrator.system_prompt
routing = orchestrator.route(user_message)
```

**Impact:** AMOS doesn't have real-time platform awareness when responding.

**Fix:** Update `ScoutGenericToolsServiceV2` to use `Amos::Orchestrator` for system prompt generation.

---

### 2. Agent Execution ↔ Context Graph

**Current State:**
- `DecisionTrace` exists for recording decisions
- `ContextGraph::DecisionRecorder` service exists
- **Agent executions don't create decision traces**

**Gap:**
```ruby
# Current: Agent executes and just records to AgentPluginExecution
agent.execute(task)

# Should be: Also create DecisionTrace
DecisionTrace.record_decision!(
  entity: entity,
  agent_plugin: agent,
  decision_type: 'action',
  decision_summary: task_summary,
  reasoning: agent_reasoning
)
```

**Impact:** No memory of WHY agents made decisions.

**Fix:** Add Context Graph integration to `AgentPluginExecutor` or create an after-execution callback.

---

### 3. Living Platform ↔ Agent Lightning

**Current State:**
- Living Platform generates goals for improvement
- Agent Lightning can optimize prompts via RL
- **Living Platform doesn't trigger Agent Lightning training**

**Gap:**
```ruby
# Current: Living Platform creates goals
goal = AgentGoal.create!(goal_type: 'improvement', agent_plugin: agent)

# Should also: Trigger training if appropriate
if goal.goal_type == 'improvement' && config.agent_lightning_enabled?
  AgentLightningTrainingService.new(entity).execute_training
end
```

**Impact:** Improvement goals don't leverage RL training.

**Fix:** Add Agent Lightning integration to goal execution.

---

### 4. Platform Evolution ↔ Agent Learning

**Current State:**
- `DebugAgentService` finds bugs and creates fixes
- `GlobalKnowledgeArchive` preserves agent knowledge
- **Bug fixes don't get archived as learned knowledge**

**Gap:**
```ruby
# Current: Bug is fixed, PR merged, done
pr.mark_merged!

# Should also: Archive the learning
GlobalKnowledgeArchive.create!(
  title: "Fix for #{ticket.error_type}",
  knowledge_type: 'lesson_learned',
  source_type: 'evolution_learning',
  content: { error: error, fix: fix, reasoning: debug_session.root_cause }
)
```

**Impact:** Same bugs can recur because learnings aren't preserved.

**Fix:** Add archive step to `GitHubPRService.mark_merged`.

---

## 🟡 Moderate Gaps (Medium Priority)

### 5. Scheduled Tasks ↔ Decision Traces

**Current State:**
- `ScheduledAgentTask` runs agents on schedules
- Executions happen but decisions aren't traced

**Fix:** Add Context Graph recording to `ExecuteScheduledAgentTaskJob`.

---

### 6. Hub ↔ Knowledge Archive

**Current State:**
- `CompanyBrainService` can search Hub messages
- Important decisions in Hub aren't archived

**Fix:** Add "archive this decision" capability to Hub messages.

---

### 7. Agent School ↔ Metacognition

**Current State:**
- `AgentSchool` diagnoses and trains agents
- `MetacognitionService` creates reflections
- **School doesn't use reflection data for diagnosis**

**Fix:** Have `AgentSchool.diagnose` pull from `AgentReflection` records.

---

### 8. Smart Router ↔ Capability Beliefs

**Current State:**
- `SmartRouterService` scores agents
- `AgentCapabilityBelief` tracks self-assessed capabilities
- **Router doesn't fully leverage capability beliefs**

**Fix:** Integrate `capability_beliefs` more deeply into routing score.

---

### 9. Factories ↔ Living Platform

**Current State:**
- Factories can create agents/tools
- Living Platform generates expansion goals
- **Goals don't automatically trigger factories**

**Fix:** Add factory invocation to goal execution for `expansion` type goals.

---

### 10. Planner ↔ Evolution Cycle

**Current State:**
- `PlannerService` breaks down complex tasks
- `EvolutionCycle` tracks platform evolution
- **Complex evolution tasks aren't planned**

**Fix:** Use Planner for multi-step evolution goals.

---

## 🟢 Minor Gaps (Lower Priority)

### 11. Memory ↔ Agent Handoffs

When an agent hands off to another, context should flow automatically.

### 12. Benchmarks ↔ Living Platform

Benchmark results should feed into perception/anomaly detection.

### 13. Voice ↔ Context Graph

Voice interactions should create decision traces.

### 14. Integrations ↔ Learning

Integration failures should create learning opportunities.

### 15. A/B Tests ↔ Metacognition

Test results should trigger reflections.

---

## 🛠️ Fix Implementation Plan

### Phase 1: Critical (This Sprint)
1. Wire Orchestrator into Scout
2. Add Context Graph to agent execution
3. Connect Living Platform to Agent Lightning

### Phase 2: Important (Next Sprint)
4. Archive bug fix learnings
5. School uses reflections
6. Router uses capability beliefs

### Phase 3: Enhancement (Backlog)
7-15. Minor gaps as time permits

---

## 📊 Gap Severity Matrix

| Gap | Impact | Effort | Priority |
|-----|--------|--------|----------|
| Orchestrator ↔ Scout | HIGH | LOW | 🔴 Critical |
| Execution ↔ Context Graph | HIGH | MEDIUM | 🔴 Critical |
| Living Platform ↔ Agent Lightning | MEDIUM | LOW | 🔴 Critical |
| Evolution ↔ Knowledge Archive | MEDIUM | LOW | 🔴 Critical |
| Scheduled Tasks ↔ Traces | MEDIUM | LOW | 🟡 Medium |
| Hub ↔ Archive | LOW | MEDIUM | 🟡 Medium |
| School ↔ Metacognition | MEDIUM | LOW | 🟡 Medium |
| Router ↔ Beliefs | MEDIUM | MEDIUM | 🟡 Medium |
| Factories ↔ Living Platform | MEDIUM | MEDIUM | 🟡 Medium |
| Planner ↔ Evolution | LOW | HIGH | 🟢 Low |


