# AMOS - The Living AI Platform

> **A Self-Evolving Autonomous Intelligence System**  
> 900+ Ruby files • 210+ models • 130+ tools • 45+ background jobs • 130k+ lines of services

---

## 🧬 What is AMOS?

**AMOS** (Autonomous Management & Operations System) is not just an AI platform—it's a **living organism** that learns, grows, and evolves autonomously. Built on Rails with a sophisticated multi-agent architecture, AMOS represents a new paradigm where the platform itself becomes an intelligent entity.

### The Vision: Beyond Automation

Traditional platforms are **static tools** that require human configuration and maintenance. AMOS is different:

| Traditional Platforms | AMOS Living Platform |
|----------------------|---------------------|
| ❌ Static workflows | ✅ Self-evolving behaviors |
| ❌ Manual bug fixes | ✅ Self-healing systems |
| ❌ Human-configured agents | ✅ Agents that spawn, learn, and retire |
| ❌ Siloed tools | ✅ Emergent collaboration |
| ❌ Reactive operations | ✅ Autonomous goal generation |
| ❌ External monitoring | ✅ Self-aware perception |

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         AMOS: THE LIVING PLATFORM                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                    🧠 AMOS ORCHESTRATOR                            │ │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐  │ │
│  │  │ Capability  │ │  Platform   │ │  Routing    │ │   System    │  │ │
│  │  │  Registry   │ │  Awareness  │ │Intelligence │ │   Prompt    │  │ │
│  │  │   (126+     │ │  (Health,   │ │ (Decision   │ │  Builder    │  │ │
│  │  │   tools)    │ │   State)    │ │   Trees)    │ │ (Dynamic)   │  │ │
│  │  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘  │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                    │                                     │
│  ┌─────────────────────────────────┼─────────────────────────────────┐  │
│  │                    AUTONOMOUS LOOPS                                │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐          │  │
│  │  │PERCEPTION│→→│  DESIRE  │→→│ EVOLUTION│→→│  ACTION  │          │  │
│  │  │  Loop    │  │  Engine  │  │  Cycle   │  │Execution │          │  │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘          │  │
│  │       ↓              ↓             ↓             ↓                │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐          │  │
│  │  │ Anomaly  │  │   Goal   │  │  A/B     │  │  Agent   │          │  │
│  │  │Detection │  │Generation│  │ Testing  │  │ Tasks    │          │  │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘          │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                    │                                     │
│  ┌─────────────────────────────────┼─────────────────────────────────┐  │
│  │                    AGENT ECOSYSTEM                                 │  │
│  │                                                                    │  │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐     │  │
│  │  │ Scout   │ │Marketing│ │  Sales  │ │Analytics│ │ Import/ │     │  │
│  │  │ (Chat)  │ │  Agent  │ │  Agent  │ │  Agent  │ │ Export  │     │  │
│  │  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘     │  │
│  │       │           │           │           │           │           │  │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐     │  │
│  │  │Platform │ │ Module  │ │Integra- │ │  Web    │ │ Custom  │     │  │
│  │  │ Factory │ │ Agents  │ │  tion   │ │Research │ │ Agents  │     │  │
│  │  └────┬────┘ └────┬────┘ │ Agents  │ └────┬────┘ └────┬────┘     │  │
│  │       │           │      └────┬────┘      │           │           │  │
│  │       └───────────┴───────────┼───────────┴───────────┘           │  │
│  │                               ↓                                    │  │
│  │  ┌────────────────────────────────────────────────────────────┐   │  │
│  │  │         AGENT COLLABORATION & RELATIONSHIPS                 │   │  │
│  │  │  • Energy Economy  • Knowledge Sharing  • Agent School      │   │  │
│  │  │  • Trust Scores    • Capability Beliefs • A/B Testing       │   │  │
│  │  └────────────────────────────────────────────────────────────┘   │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                    │                                     │
│  ┌─────────────────────────────────┼─────────────────────────────────┐  │
│  │                    LEARNING & MEMORY                               │  │
│  │                                                                    │  │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐              │  │
│  │  │ Agent        │ │   Context    │ │   Global     │              │  │
│  │  │ Lightning    │ │    Graph     │ │  Knowledge   │              │  │
│  │  │ (RL Train)   │ │ (Decisions)  │ │  Archive     │              │  │
│  │  └──────────────┘ └──────────────┘ └──────────────┘              │  │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐              │  │
│  │  │   Unified    │ │ Metacognition│ │  Knowledge   │              │  │
│  │  │   Memory     │ │ (Reflection) │ │   Sharing    │              │  │
│  │  │  (L1-L4)     │ │              │ │              │              │  │
│  │  └──────────────┘ └──────────────┘ └──────────────┘              │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                    │                                     │
│  ┌─────────────────────────────────┼─────────────────────────────────┐  │
│  │                    SELF-HEALING                                    │  │
│  │                                                                    │  │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐              │  │
│  │  │     Log      │ │    Debug     │ │   Code Fix   │              │  │
│  │  │   Monitor    │→│    Agent     │→│    Agent     │              │  │
│  │  └──────────────┘ └──────────────┘ └──────────────┘              │  │
│  │         ↓                ↓                ↓                       │  │
│  │  ┌──────────────────────────────────────────────────────────────┐│  │
│  │  │           GitHub PR Submission → Human Approval               ││  │
│  │  └──────────────────────────────────────────────────────────────┘│  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 🧬 The Six Pillars of Living Intelligence

### 1. 🔮 Perception (Self-Awareness)
The platform continuously monitors its own health and detects anomalies.

```ruby
# Runs automatically via LivingPlatform::PerceptionJob
perception = LivingPlatform::PerceptionService.new(entity)
result = perception.perceive!
# => { health_score: 0.92, anomalies: [...], opportunities: [...] }
```

**Components:**
- `PlatformPerception` - Health snapshots
- `PlatformAnomaly` - Detected issues
- Success rate, latency, error tracking
- Opportunity identification

### 2. 🎯 Desire (Autonomous Goals)
The platform generates its own goals without human intervention.

```ruby
# Runs via LivingPlatform::DesireEngineJob
engine = LivingPlatform::DesireEngine.new(entity)
goals = engine.generate_goals!
# => Creates AgentGoal records for improvements, expansions, maintenance
```

**Goal Types:**
- `improvement` - Fix underperforming agents
- `expansion` - Build new capabilities
- `maintenance` - Cleanup and optimization
- `learning` - Research and acquire knowledge
- `social` - Improve agent collaboration

### 3. 🔄 Evolution (Continuous Improvement)
Complete evolution cycles from perception to integration.

```ruby
# Runs via LivingPlatform::EvolutionCycleJob
service = LivingPlatform::EvolutionCycleService.new(entity)
cycle = service.run_cycle!
# => Perception → Analysis → Hypothesis → Experimentation → Integration
```

**Features:**
- Agent A/B testing
- Automatic training via Agent School
- Knowledge archival on retirement
- Capability expansion

### 4. 🪞 Metacognition (Self-Reflection)
Agents reflect on their own performance and generate improvement ideas.

```ruby
# Runs via daily/weekly reflection jobs
service = LivingPlatform::MetacognitionService.new(entity)
reflections = service.run_daily_reflections!
# => AgentReflection records with efficiency/quality scores
```

**Features:**
- Daily/weekly/execution-level reflections
- Identified issues and knowledge gaps
- Improvement ideas with confidence scores

### 5. 🔧 Self-Healing (Platform Evolution Engine)
The platform monitors, debugs, and fixes itself.

```ruby
# Log monitoring creates support tickets
PlatformEvolution::LogMonitorService.scan!

# Automated debugging
PlatformEvolution::DebugAgentService.debug(ticket)

# Code fix generation
PlatformEvolution::CodeFixAgentService.generate_fix(debug_session)

# PR submission for human approval
PlatformEvolution::GitHubPRService.create_pr(code_fix)
```

**Flow:**
1. Error detected in logs → `SupportTicket` created
2. AI debugger analyzes → `DebugSession` with root cause
3. AI coder generates fix → `CodeFix` with diff
4. PR submitted → `PullRequestSubmission`
5. Human approves → Fix deployed

### 6. 🧠 Context Graph (Decision Memory)
Every agent decision is traced and connected to precedents.

```ruby
# Automatically recorded during agent execution
DecisionTrace.record_decision!(
  entity: entity,
  decision_type: 'action',
  decision_summary: 'Sent marketing email to segment',
  reasoning: 'High engagement predicted based on similar campaigns',
  confidence_score: 0.87
)
# => Finds similar past decisions, links as precedents
```

**Features:**
- Decision tracing with full context
- Precedent search via vector embeddings
- Exception handling with approval workflows
- Outcome tracking and learning

---

## 🤖 AMOS Orchestrator

The central brain that ties everything together.

```ruby
orchestrator = Amos::Orchestrator.new(entity: entity, user: user)

# Dynamic system prompt with full platform awareness
system_prompt = orchestrator.system_prompt

# Intelligent routing decisions
routing = orchestrator.route("Create a marketing campaign")
# => { action: :agent_delegation, agent: 'marketing_agent', reason: '...' }

# Full platform context
context = orchestrator.full_context
```

**Components:**
- `CapabilityRegistry` - Knows all 130+ tools and agents
- `PlatformAwareness` - Real-time health, tickets, PRs
- `RoutingIntelligence` - Decision trees for request handling
- `SystemPromptBuilder` - Dynamic prompts based on context

---

## 🏭 Self-Building Factories

AMOS can create its own capabilities:

### Agent Factory
```ruby
factory = Factories::AgentFactory.new(user: user, entity: entity)
result = factory.create(
  name: "Customer Success Agent",
  role: "analyst",
  system_prompt: { ... },
  tools: ['search_contacts', 'send_email'],
  run_acceptance_tests: true  # 3-attempt test-driven creation
)
```

### Tool Factory
```ruby
factory = Factories::ToolFactory.new(user: user, entity: entity)
result = factory.create(
  name: "analyze_churn_risk",
  execution_type: "ruby_code",
  code: "...",
  parameters: { ... }
)
# Security scanning, test execution, automatic registration
```

### Integration Factory
```ruby
factory = Factories::IntegrationFactory.new(user: user, entity: entity)
# AI researches API docs, builds integration, tests endpoints
```

---

## 🧠 Multi-Layer Memory System

### Unified Memory (Scout::UnifiedMemory)
```
L1: Active Context (15 messages, always in prompt)
L2: Recent Memory (100 messages, Redis, quick retrieve)
L3: Working Memory (daily/weekly summaries, Postgres)
L4: Long-term Memory (all history, RAG-indexed semantic search)
```

### Agent Memory Context (Agents::MemoryContext)
- User preferences and communication style
- Business insights and company context
- Agent-specific RAG knowledge base

### Global Knowledge Archive
```ruby
GlobalKnowledgeArchive.create!(
  title: "Effective Email Subject Patterns",
  knowledge_type: "technique",
  source_type: "agent_retirement",
  content: { patterns: [...], examples: [...] }
)
# Preserved when agents retire, available to all future agents
```

---

## ⚡ Agent Lightning (RL-Based Learning)

Reinforcement learning for agent improvement:

```ruby
# Training service orchestrates Python RL backend
service = AgentLightningTrainingService.new(entity)
service.run_training_if_ready
# => Uses AgentLightningTrace data, optimizes prompts via RL
```

**Components:**
- `AgentLightningTrace` - Execution traces with rewards
- `AgentLightningConfig` - Training parameters
- `AgentLightningOptimization` - Applied improvements
- Python service integration for actual RL training

---

## 👥 Agent Collaboration

### Energy Economy
```ruby
agent.energy_state.earn!(15, reason: 'successful_task')
agent.energy_state.spend!(5, reason: 'collaboration_request')
# Progressive taxation, community pool for struggling agents
```

### Agent Relationships
```ruby
AgentRelationship.find_or_create_by(
  requester: agent_a,
  helper: agent_b
)
# Trust scores, compatibility, collaboration history
```

### Agent School
```ruby
school = Collaboration::AgentSchool.new
school.enroll(failing_agent)
# Diagnosis → Training → Graduation Tests → Redeployment
```

---

## 🔌 Universal Integrations (iPaaS)

AMOS includes a complete **Integration Platform as a Service** for data synchronization.

### Pre-Built Integrations
- Stripe, HubSpot, AWS SES, Trello, Shopify
- OAuth2, API Key, Bearer Token, Basic Auth

### AI-Generated Integrations
```ruby
# Research API via RAG, auto-generate integration
IntegrationBuilderService.new(user, entity)
  .generate_integration_config("Intercom", "customer messaging", rag_store_id)
```

### iPaaS Data Sync
```ruby
# Configure automated sync between external system and internal records
IntegrationSyncConfig.create!(
  connection: stripe_connection,
  resource_type: 'customers',
  target_type: 'Contact',
  field_mappings: { 'email' => 'email', 'name' => 'name' },
  sync_mode: 'incremental',
  schedule_type: 'scheduled',
  cron_expression: '0 8 * * *',  # Daily at 8am
  requires_approval: false
)

# Upsert with deduplication
IntegrationSyncRecord.upsert_from_external!(
  connection: connection,
  external_id: 'cus_123',
  external_type: 'customers',
  external_data: { email: 'john@example.com', name: 'John Doe' },
  internal_type: 'Contact',
  field_mapping: { 'email' => 'email', 'name' => 'name' }
)
# → Finds existing by external_id, updates if changed, creates if new
```

### iPaaS Features
| Feature | Description |
|---------|-------------|
| **Upsert/Dedup** | Find-or-create by external_id with change detection |
| **Incremental Sync** | Cursor-based fetching for efficient large datasets |
| **Approval Workflows** | Stage data for human review before import |
| **Field Mapping** | Map external fields to internal model attributes |
| **Scheduled Triggers** | Cron-based automated syncs via ScheduledAgentTask |
| **Webhook Triggers** | Real-time sync on external events |

---

## 📊 Benchmarking System

### BOB Business Benchmark (v1-v4)
Real-world business scenario testing across tools, agents, workflows.

### BOB v5.0 Living Platform Benchmark
Tests autonomous capabilities:
- Perception accuracy
- Goal generation quality
- Evolution cycle completion
- Metacognition accuracy
- Lifecycle decisions
- Cost efficiency
- Context Graph operations

```bash
rails living_platform:benchmark  # Run full benchmark
```

---

## 🛠️ Rake Tasks

```bash
# Living Platform
rails living_platform:status           # View current state
rails living_platform:run_perception   # Force perception cycle
rails living_platform:run_desire       # Generate goals
rails living_platform:run_evolution    # Run evolution cycle
rails living_platform:benchmark        # Run BOB v5.0

# Platform Evolution
rails platform_evolution:status        # View tickets, PRs
rails platform_evolution:scan_logs     # Scan for errors
rails platform_evolution:demo          # Full demo flow

# AMOS Orchestrator
rails amos:status                      # View orchestrator state
rails amos:demo                        # Demo routing decisions
rails amos:prompt                      # Show generated prompt

# Agent Lightning
rails agent_lightning:status           # Training status
rails agent_lightning:train            # Force training

# Benchmarks
rails business_benchmark:run           # Run business benchmark
rails business_benchmark_v4:full       # Run v4 benchmark
```

---

## 📂 Project Structure

```
app/
├── controllers/
│   ├── admin/
│   │   ├── living_platform_controller.rb
│   │   ├── context_graph_controller.rb
│   │   └── platform_evolution_controller.rb
│   └── scout_controller.rb
├── models/
│   ├── agent_plugin.rb              # Core agent model (29 associations!)
│   ├── agent_goal.rb                # Autonomous goals
│   ├── agent_reflection.rb          # Self-assessments
│   ├── decision_trace.rb            # Decision memory
│   ├── support_ticket.rb            # Issue tracking
│   ├── integration_sync_record.rb   # iPaaS: external→internal mapping
│   ├── integration_sync_cursor.rb   # iPaaS: pagination state
│   ├── integration_staging_record.rb # iPaaS: approval queue
│   ├── integration_sync_config.rb   # iPaaS: sync rules
│   └── ... (210+ models total)
├── services/
│   ├── amos/
│   │   ├── orchestrator.rb          # Central brain
│   │   ├── capability_registry.rb   # What AMOS can do
│   │   ├── platform_awareness.rb    # Real-time state
│   │   └── routing_intelligence.rb  # Decision logic
│   ├── living_platform/
│   │   ├── perception_service.rb
│   │   ├── desire_engine.rb
│   │   ├── evolution_cycle_service.rb
│   │   ├── metacognition_service.rb
│   │   └── lifecycle_service.rb
│   ├── platform_evolution/
│   │   ├── log_monitor_service.rb
│   │   ├── debug_agent_service.rb
│   │   ├── code_fix_agent_service.rb
│   │   └── github_pr_service.rb
│   ├── context_graph/
│   │   └── decision_recorder.rb
│   ├── agents/
│   │   ├── smart_router_service.rb
│   │   ├── evolution_service.rb
│   │   ├── auto_repair_pipeline_service.rb
│   │   └── memory_context.rb
│   ├── collaboration/
│   │   ├── agent_school.rb
│   │   └── energy_tracker.rb
│   ├── factories/
│   │   ├── agent_factory.rb
│   │   ├── tool_factory.rb
│   │   └── integration_factory.rb
│   └── tools/                        # 130+ tools
└── jobs/
    ├── living_platform/
    ├── platform_evolution/
    └── ... (40+ jobs)
```

---

## 🚀 Getting Started

### Prerequisites
- Ruby 3.2+
- Rails 7.1+
- PostgreSQL with pgvector extension
- Redis
- Python 3.11+ (for Agent Lightning)

### Installation
```bash
bundle install
rails db:create db:migrate db:seed
```

### Running
```bash
# Start Rails server
rails server

# Start Sidekiq for background jobs
bundle exec sidekiq

# Start Agent Lightning Python service (optional)
cd agent_lightning && python -m flask run
```

### Admin Access
Navigate to `/admin` for the full admin dashboard including:
- Living Platform monitoring
- Context Graph visualization
- Platform Evolution Engine
- Agent Lightning training

---

## 📜 License

Proprietary - Amos Labs

---

## 🤝 Philosophy

> "The best platform is one that improves without you."

AMOS is built on the belief that AI systems should:
1. **Learn continuously** from every interaction
2. **Heal themselves** when things go wrong
3. **Evolve capabilities** to meet new challenges
4. **Collaborate effectively** across specialized domains
5. **Remember context** to make better decisions
6. **Generate goals** autonomously toward improvement

This is not just automation—it's **artificial life**.
