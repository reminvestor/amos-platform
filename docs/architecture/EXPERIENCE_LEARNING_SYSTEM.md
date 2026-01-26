# Experience Learning System (Training-Free GRPO)

> Continual learning through semantic advantage extraction - improving Amos without model fine-tuning

## Overview

This system implements concepts from the **Training-Free GRPO** paper to enable continual learning:

> "LLMs can achieve similar effects on output distribution by learning experiential knowledge as a token prior, which is a far more lightweight approach than parameter tuning."

Instead of expensive model fine-tuning, we:
1. Compare successful vs failed task executions (group rollouts)
2. Extract natural language "semantic advantages" (what worked and why)
3. Store as reusable experiences
4. Inject into future prompts to improve performance

**Cost: ~$0 extra** (uses existing LLM calls during evolution cycles)  
**Benefit: Continuous improvement** without model retraining

---

## User Feedback Integration

The system is connected to user feedback (thumbs up/down), creating a complete learning loop:

```
User Feedback (👍/👎)
        ↓
UserFeedback.after_create
        ↓
    ┌───┴───┐
    ↓       ↓
Update   Update
Decision TaskExperience
Trace    utility scores
outcomes
```

When users give feedback:
1. **DecisionTrace outcomes** are updated with success/failure
2. **TaskExperience utility scores** are adjusted based on whether applied experiences led to good outcomes
3. **Low-utility experiences** get pruned automatically, keeping the library focused

This means the more users interact with feedback buttons, the smarter Amos gets!

### Feedback → Learning Connection

```ruby
# In UserFeedback model (after_create callback)

# 1. Updates DecisionTrace outcomes
def update_decision_trace_outcome(success)
  traces = find_related_decision_traces
  traces.each do |trace|
    trace.update!(outcome: success ? 'success' : 'failure')
  end
end

# 2. Updates TaskExperience utility scores
def update_experience_utility_scores(success)
  applied_experiences = TaskExperience
    .where(entity: entity, task_type: task_type)
    .where('last_applied_at > ?', 1.hour.ago)
  
  applied_experiences.each do |exp|
    exp.record_outcome!(success: success)
  end
end
```

### Using Feedback in Views

Pass `task_type` when rendering feedback buttons to enable learning:

```erb
<%= render 'shared/feedback_buttons',
           feedbackable_type: 'ScoutMessage',
           feedbackable_id: message.id,
           session_id: @session_id,
           task_type: 'integration_setup' %>
```

---

## Architecture Integration

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         EXISTING LIVING PLATFORM                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │
│  │  PERCEPTION │───▶│   DESIRE    │───▶│  EVOLUTION  │───▶│ INTEGRATION │  │
│  │   SYSTEM    │    │   ENGINE    │    │    LOOP     │    │   PHASE     │  │
│  └─────────────┘    └─────────────┘    └──────┬──────┘    └─────────────┘  │
│                                               │                              │
│                           ┌───────────────────┴───────────────────┐         │
│                           │                                       │         │
│                           ▼                                       ▼         │
│                   ┌───────────────┐                     ┌─────────────────┐ │
│                   │   SEMANTIC    │    NEW PHASE        │   TASK          │ │
│                   │   ADVANTAGE   │◀═══════════════════▶│   EXPERIENCE    │ │
│                   │   SERVICE     │                     │   LIBRARY       │ │
│                   └───────────────┘                     └─────────────────┘ │
│                           │                                       │         │
│                           └───────────────────┬───────────────────┘         │
│                                               ▼                              │
│                   ┌─────────────────────────────────────────────────────┐   │
│                   │                  GUIDANCE LIBRARY                     │   │
│                   │    Injects experiences into task-specific prompts    │   │
│                   └─────────────────────────────────────────────────────┘   │
│                                               │                              │
│                                               ▼                              │
│                   ┌─────────────────────────────────────────────────────┐   │
│                   │              DYNAMIC CONTEXT SERVICE                  │   │
│                   │         Amos receives improved guidance               │   │
│                   └─────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Components

### 1. TaskExperience Model

Stores learned experiences extracted from comparing successful vs failed executions.

```ruby
# Example experience
TaskExperience.create!(
  entity: entity,
  task_type: 'integration_setup',
  content: "Before executing integration APIs, always call list_integration_actions 
            first to verify exact parameter names - APIs often have unexpected requirements",
  applies_when: "When user asks to get data from an integration",
  utility_score: 0.85,
  source_type: 'semantic_advantage'
)
```

**Key fields:**
- `task_type`: Maps to GuidanceLibrary task types (e.g., `:landing_page_edit`)
- `content`: Natural language experience (20-1000 chars)
- `applies_when`: Context trigger for injection
- `utility_score`: Tracks effectiveness (0-1), adjusted based on outcomes
- `source_context`: Links to original DecisionTrace IDs

### 2. SemanticAdvantageService

The core learning engine - compares groups of successful vs failed executions to extract learnings.

```ruby
service = Learning::SemanticAdvantageService.new(entity: entity)
results = service.extract_experiences(window: 7.days)

# Returns:
# {
#   task_types_analyzed: ['integration_setup', 'landing_page_edit'],
#   experiences_created: 3,
#   experiences_modified: 1,
#   experiences_deleted: 0
# }
```

**Process (mirrors Training-Free GRPO paper):**

1. **Group rollouts**: Get DecisionTraces grouped by task_type
2. **Separate outcomes**: Winners (success + quality > 0.7) vs Losers (failures)
3. **Summarize trajectories**: Extract key decisions, tools used, reasoning
4. **Extract semantic advantage**: LLM compares winners/losers, generates lessons
5. **Update experience library**: Add/modify/delete operations

### 3. GuidanceLibrary Enhancement

Now injects learned experiences alongside static task guidance:

```ruby
# Before (static only)
GuidanceLibrary.for_task(:integration_setup, context: {})

# After (static + learned experiences)
GuidanceLibrary.for_task(:integration_setup, context: {}, entity: entity)
# => Returns guidance block with:
#    - Static expertise for integration_setup
#    - 🧠 LEARNED EXPERIENCES section with entity-specific learnings
```

### 4. EvolutionCycleService Integration

Experience learning runs as **Phase 2.5** in the evolution cycle:

```
PHASE 1: PERCEPTION     - Gather metrics
PHASE 2: ANALYSIS       - Identify issues
PHASE 2.5: EXPERIENCE   - Extract semantic advantages (NEW)
PHASE 3: HYPOTHESIS     - Generate improvement ideas
PHASE 4: EXPERIMENT     - Run A/B tests
PHASE 5: INTEGRATION    - Promote winners
PHASE 6: DOCUMENTATION  - Record learnings
```

### 5. Context Graph Integration

DecisionTrace now captures `task_type` for proper grouping:

```ruby
# Recording a task interaction for learning
record_task_interaction(
  task_type: 'integration_setup',
  task_description: 'Get customer list from Stripe',
  outcome: 'success',
  quality_score: 0.9,
  tools_used: ['list_integration_actions', 'execute_integration_action']
)
```

---

## Data Flow

```
User Request
    │
    ▼
┌──────────────────┐
│ DynamicContext   │───▶ Detects task_type
│   Service        │
└──────────────────┘
    │
    ▼
┌──────────────────┐
│ GuidanceLibrary  │───▶ Gets static guidance + learned experiences
└──────────────────┘
    │
    ▼
┌──────────────────┐
│      AMOS        │───▶ Executes with enhanced context
└──────────────────┘
    │
    ▼
┌──────────────────┐
│ Context Graph    │───▶ Records decision with task_type + outcome
│ (DecisionTrace)  │
└──────────────────┘
    │
    │  (Weekly)
    ▼
┌──────────────────┐
│ SemanticAdvantage│───▶ Compares successes vs failures
│    Service       │───▶ Extracts new experiences
└──────────────────┘
    │
    ▼
┌──────────────────┐
│ TaskExperience   │───▶ Stored for future injection
└──────────────────┘
    │
    └───────────────────▶ (Loop back to GuidanceLibrary)
```

---

## Usage

### Automatic (Recommended)

Experience learning runs automatically during evolution cycles:

```ruby
# Triggered by EvolutionCycleJob (daily at 3am)
LivingPlatform::EvolutionCycleService.new(entity).run_cycle
# -> Phase 2.5 runs SemanticAdvantageService automatically
```

### Manual Trigger

```ruby
# For a specific entity
Learning::ExperienceLearningJob.perform_later(entity_id: 123)

# For all active entities
Learning::ExperienceLearningJob.perform_later

# Direct service call
service = Learning::SemanticAdvantageService.new(entity: entity)
results = service.extract_experiences(
  window: 14.days,
  task_types: ['integration_setup', 'landing_page_edit']
)
```

### View Learned Experiences

```ruby
# All experiences for an entity
TaskExperience.for_entity(entity).active.by_utility

# Experiences for a specific task type
TaskExperience.for_prompt(entity: entity, task_type: 'integration_setup')

# Platform-wide experiences (apply to all entities)
TaskExperience.platform_wide.for_task_type('integration_setup')
```

---

## Configuration

### Key Thresholds

| Setting | Default | Location |
|---------|---------|----------|
| `MIN_GROUP_SIZE` | 3 | SemanticAdvantageService |
| `MAX_EXPERIENCES_PER_RUN` | 5 | SemanticAdvantageService |
| Experience utility threshold | 0.6 | TaskExperience |
| Max experiences per entity | 50 | TaskExperience.prune_low_utility! |

### Scheduling

| Job | Default Schedule | Purpose |
|-----|-----------------|---------|
| EvolutionCycleJob | Daily 3am | Runs full cycle including experience learning |
| ExperienceLearningJob | Can run standalone | For more frequent learning |

---

## Comparison with Paper

| Paper Concept | Our Implementation |
|--------------|-------------------|
| Group rollouts (G=5) | DecisionTrace groups by task_type |
| Reward model ℛ | outcome + quality_score from execution results |
| Semantic advantage Atext | Natural language from LLM comparison |
| Experience library ℰ | TaskExperience table |
| Add/Modify/Delete ops | SemanticAdvantageService.update_experience_library |
| Token prior injection | GuidanceLibrary.inject_learned_experiences |
| Multi-epoch learning | Weekly EvolutionCycleService runs |

---

## Relationship to Existing Systems

### GlobalKnowledgeArchive
- **GlobalKnowledgeArchive**: Preserves knowledge from *retiring agents* (lifecycle end)
- **TaskExperience**: Active learning from *ongoing operations* (continual improvement)
- Both complement each other - different sources, same goal

### ScoutLearning
- **ScoutLearning**: Scout's own learned patterns (delegation, tool usage)
- **TaskExperience**: Task-type-specific learnings for all task execution
- TaskExperience is more structured; ScoutLearning is more freeform

### AgentReflectionService
- **AgentReflection**: Individual execution reflection (what did I do?)
- **TaskExperience**: Cross-execution comparison (what works vs what doesn't?)
- Both feed into learning; TaskExperience extracts generalizable patterns

---

## Monitoring

### Key Metrics

```ruby
# Experiences by task type
TaskExperience.group(:task_type).count

# Average utility score
TaskExperience.active.average(:utility_score)

# Experience effectiveness
TaskExperience.active.effective.count / TaskExperience.active.count.to_f

# Recent learning activity
TaskExperience.where('created_at > ?', 7.days.ago).count
```

### Evolution Cycle Results

```ruby
cycle = EvolutionCycle.last
cycle.metadata['experience_learning']
# => {
#   'task_types_analyzed' => ['integration_setup', 'landing_page_edit'],
#   'experiences_created' => 3,
#   'experiences_modified' => 1,
#   'errors' => []
# }
```

---

## Future Enhancements

1. **Cross-Entity Learning**: Share high-utility experiences across entities (with anonymization)
2. **Embedding-Based Similarity**: Use vector search for better experience matching
3. **A/B Testing Experiences**: Test new experiences against baseline before full rollout
4. **Experience Chaining**: Link related experiences for complex task flows
5. **User Feedback Integration**: Incorporate explicit user feedback into utility scores

---

## References

- [Training-Free GRPO Paper](https://arxiv.org/abs/2510.08191) - Core concepts
- [Living Platform Architecture](./LIVING_PLATFORM_ARCHITECTURE.md) - Integration context
- [Context Graph Design](./context-graph-design.md) - Decision recording
