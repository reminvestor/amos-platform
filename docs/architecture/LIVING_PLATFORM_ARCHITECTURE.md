# Living Platform Architecture

> A self-evolving AI platform that learns, grows, and improves autonomously

## Overview

The Living Platform transforms the agent system into a true "living organism" - a platform that can observe itself, generate its own goals, learn from experience, and continuously improve without human intervention.

## Philosophy

The platform operates on the principle that **an AI system should be able to improve itself**. Just as biological organisms adapt and evolve, this platform:

1. **Perceives** its environment and internal state
2. **Desires** specific outcomes based on analysis
3. **Acts** to achieve those desires
4. **Reflects** on the results
5. **Evolves** based on learnings

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         LIVING PLATFORM                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │
│  │  PERCEPTION │───▶│   DESIRE    │───▶│  EVOLUTION  │───▶│ INTEGRATION │  │
│  │   SYSTEM    │    │   ENGINE    │    │    LOOP     │    │   PHASE     │  │
│  └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘  │
│        │                   │                   │                  │         │
│        ▼                   ▼                   ▼                  ▼         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        METACOGNITION LAYER                           │   │
│  │    Agent Self-Reflection • Learning • Knowledge Gaps                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         LIFECYCLE SYSTEM                             │   │
│  │    Birth • Training • Maturation • Retirement • Knowledge Archive   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        EXISTING SYSTEMS (Extended)                           │
├─────────────────────────────────────────────────────────────────────────────┤
│  Agent School │ Evolution Service │ Agent Relationships │ Energy System     │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Core Systems

### 1. Perception System (`LivingPlatform::PerceptionService`)

The platform's "senses" - continuous monitoring of health and detection of anomalies.

**Capabilities:**
- Gathers metrics on agent performance, success rates, and activity
- Detects anomalies (performance drops, error spikes, stale agents)
- Identifies opportunities (high performers, underutilized capacity)
- Detects threats (critical issues, declining health trends)
- Triggers autonomous actions for critical issues

**Schedule:** Runs hourly via `LivingPlatform::PerceptionJob`

**Key Model:** `PlatformPerception`, `PlatformAnomaly`

**Example Output:**
```ruby
{
  overall_health_score: 0.82,
  active_agents: 15,
  success_rate_24h: 0.87,
  anomalies: 2,
  critical_anomalies: 0,
  opportunities: [
    { type: 'high_performer', agent: 'research_agent' }
  ]
}
```

---

### 2. Desire Engine (`LivingPlatform::DesireEngine`)

The platform's "motivation" - generates autonomous goals without human intervention.

**Goal Types:**
- **Improvement**: Make underperforming agents better
- **Expansion**: Build new capabilities for unmet needs
- **Maintenance**: Fix, clean, or optimize components
- **Learning**: Research and acquire new knowledge
- **Social**: Improve agent collaboration

**Process:**
1. Analyze performance metrics from Perception
2. Identify underperforming agents and skill gaps
3. Detect unmet user needs from rejected proposals
4. Find collaboration weaknesses
5. Generate prioritized goals
6. Schedule goals for execution

**Schedule:** Runs daily at 1am via `LivingPlatform::DesireEngineJob`

**Key Model:** `AgentGoal`

---

### 3. Evolution Cycle (`LivingPlatform::EvolutionCycleService`)

The platform's "growth" - a complete cycle of improvement from hypothesis to deployment.

**Phases:**

1. **PERCEIVE**: Gather metrics and detect anomalies
2. **ANALYZE**: Understand what's working and what's not
3. **HYPOTHESIZE**: Generate ideas for improvement
4. **EXPERIMENT**: Run A/B tests on promising changes
5. **INTEGRATE**: Promote successful experiments
6. **DOCUMENT**: Record what was learned

**Integration with Existing Systems:**
- Uses `Agents::EvolutionService` for agent analysis
- Uses `AgentAbTest` for experiments
- Uses `Collaboration::AgentSchool` for training

**Schedule:** Daily at 3am, Weekly on Sundays at 4am

**Key Model:** `EvolutionCycle`

---

### 4. Metacognition Layer (`LivingPlatform::MetacognitionService`)

The platform's "self-awareness" - agents reflect on their own performance.

**Reflection Types:**
- **Execution**: After task completion (sampled 30%)
- **Daily**: End-of-day summary
- **Weekly**: Comprehensive performance review

**What Agents Reflect On:**
- Efficiency score (1-10)
- Quality score (1-10)
- Tool usage score (1-10)
- Communication score (1-10)
- Identified issues
- Improvement ideas
- Knowledge gaps
- Strengths identified

**Outcomes:**
- Low-performing agents can trigger their own enrollment in Agent School
- Knowledge gaps feed into Desire Engine for learning goals
- Discovered specializations are recorded

**Schedule:** Daily reflections at 11pm, Weekly on Sundays at 10pm

**Key Model:** `AgentReflection`

---

### 5. Lifecycle System (`LivingPlatform::LifecycleService`)

The platform's "biology" - manages agent birth, maturation, and retirement.

**Lifecycle Stages:**
1. **Birth**: New agent created based on detected needs
2. **Training**: Agent goes through learning curriculum
3. **Active**: Fully operational agent
4. **Mature**: Proven agent with established track record
5. **Retiring**: Deprecated, being phased out
6. **Retired**: Archived, knowledge preserved

**Key Features:**
- Auto-generates agents from detected unmet needs
- Integrates with Agent School for training
- Evaluates agents for retirement based on:
  - Inactivity (90+ days)
  - Poor performance (70%+ failure rate)
  - Being superseded by better agents
- Preserves knowledge from retiring agents via `GlobalKnowledgeArchive`
- Can resurrect retired agents if needed

**Schedule:** Daily at 2am via `LivingPlatform::LifecycleEvaluationJob`

**Key Models:** `AgentLifecycleEvent`, `GlobalKnowledgeArchive`

---

## Integration with Existing Systems

### Agent School Integration

The Living Platform extends Agent School, not replaces it:

```
Detection (Perception) → Goal (Desire Engine) → Enrollment (Agent School) → Graduation → Lifecycle Event
```

When the Desire Engine creates an improvement goal for an agent:
1. Goal can trigger `AgentSchoolEnrollment`
2. Agent School handles the curriculum and graduation
3. Lifecycle Service records maturation event

### Evolution Service Integration

The existing `Agents::EvolutionService` is used by:
- `DesireEngine` for analyzing agent performance
- `EvolutionCycleService` for comprehensive analysis
- `MetacognitionService` for peer comparison

### Agent Relationships Integration

`AgentRelationship` is extended with:
- `knowledge_shares_count` - Track knowledge sharing
- `last_knowledge_share_at` - Recent sharing activity
- `relationship_type` - peer, mentor_mentee, specialist_generalist

---

## Database Schema

### New Tables

| Table | Purpose |
|-------|---------|
| `agent_goals` | Autonomous goals generated by Desire Engine |
| `evolution_cycles` | Complete evolution iteration records |
| `agent_reflections` | Agent metacognition records |
| `platform_perceptions` | Platform health snapshots |
| `platform_anomalies` | Detected anomalies |
| `agent_lifecycle_events` | Agent birth, maturation, retirement records |
| `global_knowledge_archives` | Preserved knowledge from agents |
| `agent_knowledge_shares` | Knowledge sharing between agents |

### Extended Tables

| Table | New Fields |
|-------|------------|
| `agent_plugins` | `lifecycle_stage`, `generation`, `parent_agent_ids`, `discovered_specializations`, `last_reflection_at`, `last_evolution_at`, `evolution_count`, `autonomous_goals_enabled` |
| `agent_ab_tests` | `evolution_cycle_id`, `agent_goal_id` |
| `agent_school_enrollments` | `triggered_by_goal_id`, `evolution_cycle_id` |
| `agent_plugin_executions` | `evolution_experiment_id`, `is_experiment_control`, `reflection_generated` |
| `agent_relationships` | `knowledge_shares_count`, `last_knowledge_share_at`, `relationship_type` |

---

## Scheduled Jobs

| Job | Schedule | Purpose |
|-----|----------|---------|
| `PerceptionJob` | Every hour | Monitor health, detect anomalies |
| `DesireEngineJob` | Daily 1am | Generate autonomous goals |
| `EvolutionCycleJob` | Daily 3am, Weekly Sunday 4am | Full improvement cycle |
| `DailyAgentReflectionsJob` | Daily 11pm | End-of-day agent reflections |
| `WeeklyAgentReflectionsJob` | Weekly Sunday 10pm | Comprehensive weekly review |
| `LifecycleEvaluationJob` | Daily 2am | Check training, retirement |

---

## A Day in the Life of the Platform

```
00:00 ─┬─ Platform operates normally, agents execute tasks
       │
01:00 ─┼─ 🎯 Desire Engine: Generates daily goals based on detected needs
       │
02:00 ─┼─ 🔄 Lifecycle Evaluation: Checks training completion, retirement candidates
       │
03:00 ─┼─ 🧬 Evolution Cycle: Full perception → analysis → experiment → integrate cycle
       │
       │  (Throughout the day)
       │
       │  Every hour: 👁️ Perception runs, detects anomalies, triggers urgent actions
       │  After tasks: 🧠 Agents reflect on performance (sampled)
       │
23:00 ─┼─ 💭 Daily Reflections: All active agents summarize their day
       │
23:59 ─┴─ Day completes, cycle repeats
```

---

## Usage Examples

### Triggering Manual Evolution Cycle

```ruby
entity = Entity.find(1)
service = LivingPlatform::EvolutionCycleService.new(entity)
cycle = service.run_cycle(type: 'triggered')

puts cycle.summary
# => {
#   experiments_started: 2,
#   experiments_completed: 0,
#   goals_generated: 5
# }
```

### Creating an Agent from Detected Need

```ruby
need = {
  description: "Users need a financial analysis agent",
  request_count: 15,
  sample_requests: ["Analyze my Q3 financials", "Create budget forecast"]
}

service = LivingPlatform::LifecycleService.new(entity)
agent = service.birth_agent(
  need: need,
  trigger: 'desire_engine',
  parent_agents: [research_agent, data_agent]
)

# Agent is created in training stage, curriculum is generated
puts agent.lifecycle_stage  # => "training"
puts agent.generation       # => 3 (inherits from parent generations)
```

### Getting Platform Health

```ruby
perception = PlatformPerception.latest_for_entity(entity)

puts perception.health_status     # => "good"
puts perception.anomaly_count     # => 2
puts perception.opportunities     # => [{type: 'high_performer', ...}]

trend = PlatformPerception.health_trend(entity, days: 7)
puts trend  # => "improving"
```

### Agent Self-Reflection

```ruby
agent = AgentPlugin.find_by(slug: 'research_agent')
service = LivingPlatform::MetacognitionService.new(agent)

reflection = service.weekly_reflection

puts reflection.overall_score         # => 8
puts reflection.discovered_specializations  # => ["data analysis", "research"]
puts reflection.peer_comparison       # => { percentile: 85 }
```

---

## Configuration

### Enabling/Disabling Autonomous Goals

```ruby
# Disable autonomous goals for a specific agent
agent.update!(autonomous_goals_enabled: false)

# The Desire Engine will skip this agent when generating goals
```

### Thresholds

Key thresholds can be adjusted in the service classes:

| Setting | Default | Location |
|---------|---------|----------|
| `IMPROVEMENT_THRESHOLD` | 0.7 | DesireEngine |
| `INACTIVITY_THRESHOLD_DAYS` | 90 | LifecycleService |
| `FAILURE_RATE_THRESHOLD` | 0.7 | LifecycleService |
| `REFLECTION_SAMPLE_RATE` | 0.3 | MetacognitionService |
| `MAX_EXPERIMENTS_PER_CYCLE` | 3 | EvolutionCycleService |

---

## Monitoring

### Key Metrics to Watch

1. **Platform Health Score**: Overall health from Perception (target: > 0.8)
2. **Evolution Velocity**: Successful promotions per week
3. **Experiment Success Rate**: % of experiments that lead to improvements
4. **Goal Completion Rate**: % of autonomous goals completed
5. **Agent Generation Average**: How "evolved" is the agent population

### Dashboard Queries

```ruby
# Platform health trend
PlatformPerception.health_trend(entity, days: 7)
# => "improving" | "stable" | "declining"

# Evolution velocity
EvolutionCycle.evolution_velocity(entity, days: 30)
# => 2.5 (promotions per week)

# Goal completion rate
completed = AgentGoal.where(entity: entity, status: 'completed').count
total = AgentGoal.where(entity: entity).count
rate = completed.to_f / total
# => 0.75
```

---

## Future Enhancements

1. **Cross-Entity Learning**: Share learnings across entities
2. **Predictive Goals**: Anticipate needs before they arise
3. **Agent Breeding**: Combine successful agents into new specialists
4. **Knowledge Graph**: Visual map of agent knowledge and relationships
5. **External Perception**: Monitor external factors (API health, user patterns)

---

## Related Documentation

- [Agent Collaboration Architecture](./AGENT_COLLABORATION_ARCHITECTURE.md)
- [Extensible Module System](./EXTENSIBLE_MODULE_SYSTEM.md)
- [Agent Lightning Integration](../AGENT_LIGHTNING_INTEGRATION.md)


