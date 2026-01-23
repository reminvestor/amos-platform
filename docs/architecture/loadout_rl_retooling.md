# Loadout & RL System Retooling Analysis

## Executive Summary

With the plugin injection architecture, agents are now **loadouts** that enhance Amos rather than separate entities. This dramatically simplifies the learning and evolution system while making it MORE powerful - we're now optimizing a single AI's specializations rather than managing a zoo of semi-independent agents.

---

## Current Systems Inventory

### 1. Agent Learning Service (`agent_learning_service.rb`)
**What it does:**
- Tracks success/failure patterns per agent type
- Extracts successful prompts for reuse
- Suggests improvements based on performance metrics
- Uses simple pattern matching and caching

**Status:** ⚠️ Needs Retooling
- Currently tied to `agent_type` concept
- Stores patterns per-agent, but should now track per-loadout

### 2. Evolution Service (`agents/evolution_service.rb`)
**What it does:**
- Analyzes agent performance over 30 days
- Identifies skill gaps and missing tools
- Generates training recommendations
- Triggers "Agent School" enrollment for struggling agents

**Status:** 🔄 Major Refactor Needed
- Built for separate agents with AgentTaskProposal routing
- Evolution = prompt/tool changes should now apply to loadouts
- A/B testing concept still valid but simpler

### 3. Agent School (`collaboration/agent_school.rb`)
**What it does:**
- Enrolls failing agents (zero energy)
- Diagnoses failure patterns
- Creates "student" variants with improved prompts
- Runs graduation A/B tests
- Probation, expulsion, replacement logic

**Status:** ❌ Over-Engineered for New Model
- The whole "clone agent, test variant, graduate" flow is overkill
- With loadouts, we just tweak the loadout definition directly
- No need for "in_school" status on agents

### 4. Execution Learning Bridge (`execution_learning_bridge.rb`)
**What it does:**
- Records unfulfilled intents (AI says "I'll do X" but doesn't)
- Tracks execution loops
- Records stuck executions
- Updates capability beliefs

**Status:** ✅ Keep & Adapt
- Core detection logic is good
- Just needs to target loadouts instead of agents
- Integrates with notification service (still useful)

### 5. Dynamic Energy Pricer (`collaboration/dynamic_energy_pricer.rb`)
**What it does:**
- Calculates energy costs for collaboration
- Rewards for helping other agents
- Failure penalties and success rewards

**Status:** ❌ Not Needed
- No inter-agent collaboration in plugin model
- Energy system was for agent resource management
- Amos doesn't have "energy" - he's always available

### 6. Unified Memory (`scout/unified_memory.rb`)
**What it does:**
- L1-L4 memory layers for Amos
- Cross-session memory
- Proactive memory warming

**Status:** ✅ Keep As-Is
- This is Amos's memory, not agent memory
- Works perfectly with plugin injection

---

## The New Mental Model

```
┌─────────────────────────────────────────────────────────────┐
│                         AMOS                                 │
│  (Single AI with unified memory and core identity)           │
├─────────────────────────────────────────────────────────────┤
│                    LOADOUT LAYER                             │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐            │
│  │ Landing Page│ │  Workflow   │ │    CRM      │  ...       │
│  │   Manager   │ │  Architect  │ │   Expert    │            │
│  └─────────────┘ └─────────────┘ └─────────────┘            │
│       ↓ prompt        ↓ prompt        ↓ prompt               │
│       ↓ tools         ↓ tools         ↓ tools                │
├─────────────────────────────────────────────────────────────┤
│                   LEARNING LAYER                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │            LoadoutOptimizationService                │    │
│  │  - Track per-loadout success/failure metrics         │    │
│  │  - Detect hallucination patterns                      │    │
│  │  - A/B test prompt variations                         │    │
│  │  - Auto-adjust tool assignments                       │    │
│  │  - Quality scoring per canvas context                 │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

---

## Proposed New Architecture

### 1. **LoadoutOptimizationService** (Replaces AgentLearningService + EvolutionService)

```ruby
class LoadoutOptimizationService
  # Core metrics tracking
  def record_interaction(loadout_slug:, canvas:, success:, details:)
    # Track: tool_calls, hallucinations, user_satisfaction, response_quality
  end
  
  # Pattern detection
  def detect_patterns(loadout_slug:, window: 7.days)
    # Find: repeated failures, hallucination trends, tool misuse
  end
  
  # Optimization recommendations  
  def suggest_improvements(loadout_slug:)
    # Generate: prompt tweaks, tool additions/removals, guardrail additions
  end
  
  # A/B testing (simplified)
  def run_ab_test(loadout_slug:, variant_prompt:, sample_size: 100)
    # Split traffic, measure quality, auto-promote winner
  end
  
  # Auto-apply safe improvements
  def auto_optimize(loadout_slug:)
    # Apply low-risk improvements automatically
    # Queue high-risk changes for review
  end
end
```

### 2. **LoadoutHealthMonitor** (Replaces AgentSchool)

```ruby
class LoadoutHealthMonitor
  # Health check (no enrollment/graduation - just monitoring)
  def health_score(loadout_slug:)
    {
      success_rate: 0.87,
      hallucination_rate: 0.03,
      avg_response_quality: 0.82,
      tool_usage_accuracy: 0.95,
      trend: :improving  # or :stable, :declining
    }
  end
  
  # Alert when loadout is degrading
  def check_alerts
    # Notify admin if any loadout health drops below threshold
  end
  
  # Quick fix application
  def apply_emergency_fix(loadout_slug:, fix_type:)
    # Apply known fixes: add anti-hallucination prompt, restrict tools, etc.
  end
end
```

### 3. **LoadoutMetrics** (New - Simple Tracking Table)

```ruby
# Migration
create_table :loadout_metrics do |t|
  t.string :loadout_slug, null: false
  t.references :entity, null: false
  t.string :canvas_context
  t.string :event_type  # 'success', 'failure', 'hallucination', 'tool_call'
  t.jsonb :details, default: {}
  t.float :quality_score
  t.timestamps
end

add_index :loadout_metrics, [:loadout_slug, :created_at]
add_index :loadout_metrics, [:entity_id, :loadout_slug]
```

### 4. **LoadoutVersion** (New - Track Prompt/Tool Changes)

```ruby
# Migration  
create_table :loadout_versions do |t|
  t.references :agent_plugin, null: false  # The loadout
  t.integer :version_number, null: false
  t.text :system_prompt_snapshot
  t.jsonb :tools_snapshot, default: []
  t.string :change_reason
  t.references :changed_by, polymorphic: true  # User or System
  t.jsonb :performance_before, default: {}
  t.jsonb :performance_after, default: {}
  t.timestamps
end
```

---

## What to DELETE

| System | Why Delete |
|--------|-----------|
| `AgentSchool` | Over-complex for loadouts. No need for enrollment/graduation ceremonies. |
| `AgentSchoolEnrollment` model | Not needed |
| `AgentAbTest` model | Replace with simpler A/B in LoadoutOptimizationService |
| `AgentEnergyState` model | No energy system needed |
| `DynamicEnergyPricer` | No inter-agent collaboration |
| `EnergyTracker` | No energy system |
| `AgentTaskProposal` | No task routing between agents |
| `AgentInputRequest` | No agent questions - Amos asks directly |
| `CollaborationRequest` | No inter-agent collaboration |

## What to KEEP & ADAPT

| System | Adaptation |
|--------|-----------|
| `ExecutionLearningBridge` | Change `agent` to `loadout_slug`, keep detection logic |
| `AgentLearningService` | Rename to LoadoutLearningService, track by loadout_slug |
| `UnifiedMemory` | Keep as-is (Amos's memory) |
| `AgentPlugin` model | Repurpose as "Loadout" definition store |

---

## Migration Plan

### Phase 1: Create New Infrastructure (Non-Breaking)
1. Create `LoadoutMetrics` table
2. Create `LoadoutVersion` table  
3. Create `LoadoutOptimizationService`
4. Create `LoadoutHealthMonitor`

### Phase 2: Instrument Plugin Injection
1. Add metrics recording to `PluginInjectionService`
2. Track success/failure in `ScoutGenericToolsServiceV2`
3. Hook hallucination detection to metrics

### Phase 3: Deprecate Old Systems
1. Stop using AgentSchool, AgentEnergy, etc.
2. Mark old models as deprecated
3. Stop running related background jobs

### Phase 4: Cleanup
1. Remove deprecated code
2. Drop unused tables
3. Update documentation

---

## Simplified RL Loop

```
┌─────────────────┐
│  User Request   │
└────────┬────────┘
         ↓
┌─────────────────┐
│ Plugin Injection│───→ Record: loadout used, canvas context
└────────┬────────┘
         ↓
┌─────────────────┐
│ Amos + Loadout  │───→ Record: tool calls, response
└────────┬────────┘
         ↓
┌─────────────────┐
│ Quality Check   │───→ Detect: hallucinations, failures
└────────┬────────┘
         ↓
┌─────────────────┐
│ Metrics Storage │───→ Store: success/failure, quality score
└────────┬────────┘
         ↓
    (Background)
         ↓
┌─────────────────┐
│ Pattern Analysis│───→ Weekly: find trends, suggest improvements
└────────┬────────┘
         ↓
┌─────────────────┐
│ Auto-Optimize   │───→ Apply: safe improvements, A/B test risky ones
└─────────────────┘
```

---

## Key Metrics to Track

### Per-Loadout Metrics
- **Success Rate**: % of interactions marked successful
- **Hallucination Rate**: % of interactions with detected hallucinations
- **Tool Usage Accuracy**: % of tool calls that succeed
- **Response Quality**: Average quality score (0-1)
- **User Correction Rate**: How often users have to correct Amos after loadout use

### System-Wide Metrics
- **Loadout Coverage**: % of canvas contexts with a loadout
- **Fallback Rate**: % of requests handled by base Amos (no loadout)
- **Average Response Time**: Per-loadout latency
- **Top Performing Loadouts**: By success rate
- **Struggling Loadouts**: Need attention

---

## Summary

The plugin injection architecture makes the RL system **dramatically simpler**:

| Before | After |
|--------|-------|
| Manage 20+ agents | Manage 5-10 loadouts |
| Complex inter-agent delegation | No delegation |
| Agent energy, school, graduation | Simple metrics + auto-optimize |
| A/B testing agent variants | A/B testing prompt variations |
| Agent collaboration costs | N/A |
| Multiple conversation contexts | One conversation (Amos) |

The new system focuses on:
1. **Measuring** what matters (per-loadout success)
2. **Detecting** problems early (hallucinations, failures)
3. **Improving** automatically (prompt tweaks, tool adjustments)
4. **Keeping it simple** (no agent lifecycle management)
