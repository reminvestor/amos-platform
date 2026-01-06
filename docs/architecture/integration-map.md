# AMOS Integration Map

> How all the systems connect and communicate

---

## 🗺️ System Integration Overview

This document maps **how the 15+ major subsystems** of AMOS communicate with each other.

---

## 📊 Integration Matrix

| System | Talks To | Via | Purpose |
|--------|----------|-----|---------|
| **AMOS Orchestrator** | All systems | Service calls | Central coordination |
| **Scout/Chat** | Orchestrator, Tools, Agents | Service calls | User interface |
| **Living Platform** | Agents, Goals, Anomalies | Models + Jobs | Autonomous loops |
| **Platform Evolution** | Tickets, Debug, Git | Service chain | Self-healing |
| **Context Graph** | DecisionTrace, Embeddings | After-create hooks | Decision memory |
| **Agent Lightning** | Traces, Python service | HTTP + Models | RL training |
| **Agent Collaboration** | Relationships, Energy | Request models | Agent cooperation |
| **Agent School** | Enrollments, A/B Tests | Service | Agent training |
| **Factories** | Agents, Tools, Integrations | Service + Validation | Self-building |
| **Planner** | Execution Plans, Steps | Job + Service | Complex orchestration |
| **Hub** | Threads, Messages, Handoffs | Service + Cable | Team collaboration |
| **Unified Memory** | Redis, Postgres, RAG | Multi-layer | Context persistence |
| **Scheduled Tasks** | Jobs, Agents, Scout | Dispatcher job | Autonomy |
| **Integrations** | External APIs, Connections | HTTP | External systems |
| **Benchmarks** | All systems | Test harness | Quality assurance |

---

## 🔗 Detailed Connection Flows

### 1. User Request Flow
```
User Message
     │
     ▼
┌─────────────────┐
│ ScoutController │
│     (chat)      │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────┐
│ ScoutGenericToolsServiceV2  │
│  - preprocess_message()     │
│  - build_system_prompt()    │◀─┐
│  - process_with_tools()     │  │
└────────┬────────────────────┘  │
         │                       │
         ▼                       │
┌─────────────────────────────┐  │
│     Tool Execution          │  │
│  ┌─────────────────────┐    │  │
│  │ ToolCatalog         │    │  │
│  │  - 126+ tools       │    │  │
│  │  - get_bedrock_tools│    │  │
│  └─────────┬───────────┘    │  │
│            │                │  │
│            ▼                │  │
│  ┌─────────────────────┐    │  │
│  │ ToolRunner          │    │  │
│  │  - execute_tool()   │    │  │
│  └─────────────────────┘    │  │
└────────┬────────────────────┘  │
         │                       │
         ▼                       │
┌─────────────────────────────┐  │
│  Delegation Check           │  │
│  ├─ DelegateToAgentTool    │──┼──▶ Agent Execution
│  ├─ DelegateToPlannerTool  │──┼──▶ Planner Service
│  └─ AskAgentForHelpTool    │──┼──▶ Collaboration
└────────────────────────────┘  │
                                │
┌───────────────────────────────┘
│ UnifiedMemory
│  - L1: Active (in-memory)
│  - L2: Recent (Redis)
│  - L3: Working (Postgres)
│  - L4: Long-term (RAG)
└───────────────────────────────
```

### 2. Agent Execution Flow
```
Agent Task Request
       │
       ▼
┌──────────────────────┐
│  AgentPluginService  │
│   - discover_agent() │
│   - instantiate()    │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐     ┌───────────────────────┐
│  SmartRouterService  │◀────│ AgentTaskProposal     │
│   - score_agent()    │     │  - handshake protocol │
│   - auto_select()    │     └───────────────────────┘
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ AgentPluginExecutor  │
│   - execute()        │
└──────────┬───────────┘
           │
           ├───────────────────────────────────┐
           ▼                                   ▼
┌──────────────────────┐            ┌──────────────────────┐
│  PhaseExecutor       │            │  MemoryContext       │
│   - GoalExecutor     │            │   - user_memories    │
│   - GatherContext    │            │   - business_insights│
│   - Validation       │            │   - agent_knowledge  │
└──────────┬───────────┘            └──────────────────────┘
           │
           ▼
┌──────────────────────────────────────────────────────────┐
│  AgentPluginExecution (Record)                           │
│   - trace_id, input_context, output_result               │
│   - duration_ms, tokens_used, status                     │
└──────────┬───────────────────────────────────────────────┘
           │
           ├─────────────────────┬─────────────────────────┐
           ▼                     ▼                         ▼
┌──────────────────┐   ┌──────────────────┐    ┌──────────────────┐
│DecisionTrace     │   │AgentLightning    │    │AgentReflection   │
│ - record_decision│   │Trace             │    │ (if configured)  │
│ - find_precedents│   │ - for RL training│    │                  │
└──────────────────┘   └──────────────────┘    └──────────────────┘
```

### 3. Living Platform Autonomous Loop
```
┌─────────────────────────────────────────────────────────────────┐
│                    PERCEPTION PHASE                              │
│  (LivingPlatform::PerceptionJob - runs every 15 minutes)        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ PerceptionService.perceive!                                      │
│  ├─ Calculate health score (success rate, latency, errors)      │
│  ├─ Detect anomalies (error spikes, slow agents, failures)      │
│  ├─ Identify opportunities (underutilized, trending)            │
│  └─ Create PlatformPerception + PlatformAnomaly records         │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    DESIRE PHASE                                  │
│  (LivingPlatform::DesireEngineJob - runs daily)                 │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ DesireEngine.generate_goals!                                     │
│  ├─ Improvement goals (from underperforming agents)             │
│  ├─ Expansion goals (from capability gaps)                      │
│  ├─ Maintenance goals (from anomalies)                          │
│  ├─ Learning goals (research topics)                            │
│  └─ Create AgentGoal records with priorities                    │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    EVOLUTION PHASE                               │
│  (LivingPlatform::EvolutionCycleJob - runs weekly)              │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ EvolutionCycleService.run_cycle!                                 │
│  ├─ Phase 1: Perception (gather metrics)                        │
│  ├─ Phase 2: Analysis (rank improvements)                       │
│  ├─ Phase 3: Hypothesis (generate experiments)                  │
│  ├─ Phase 4: Experimentation (run A/B tests via AgentAbTest)    │
│  ├─ Phase 5: Integration (apply winning changes)                │
│  └─ Phase 6: Documentation (archive learnings)                  │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ACTION PHASE                                  │
│  Goals executed via ScheduledAgentTask or direct agent calls    │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ Connected Systems:                                               │
│  ├─ AgentSchool (for training goals)                            │
│  ├─ AgentAbTest (for improvement experiments)                   │
│  ├─ GlobalKnowledgeArchive (for knowledge goals)                │
│  ├─ Factories (for expansion goals)                             │
│  └─ EvolutionService (for agent evolution)                      │
└─────────────────────────────────────────────────────────────────┘
```

### 4. Self-Healing Flow
```
┌─────────────────────────────────────────────────────────────────┐
│                    ERROR DETECTION                               │
│  (PlatformEvolution::LogMonitorJob - runs every 5 minutes)      │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ LogMonitorService.scan!                                          │
│  ├─ Parse Rails logs for errors/exceptions                      │
│  ├─ Group by error signature                                    │
│  ├─ Create ErrorLogEntry records                                │
│  └─ Create SupportTicket if new error pattern                   │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ User-Reported Issues (Alternative Path)                          │
│  ├─ User tells AMOS about a bug                                 │
│  ├─ CreateSupportTicketTool invoked                             │
│  └─ SupportTicket created with user context                     │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    DEBUG PHASE                                   │
│  (PlatformEvolution::DebugAgentJob - triggered by ticket)       │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ DebugAgentService.debug(ticket)                                  │
│  ├─ Gather error context (logs, traces, recent changes)         │
│  ├─ AI analysis to find root cause                              │
│  ├─ Generate hypothesis and solution approach                   │
│  └─ Create DebugSession with findings                           │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    FIX PHASE                                     │
│  (PlatformEvolution::CodeFixJob - triggered by debug session)   │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ CodeFixAgentService.generate_fix(debug_session)                  │
│  ├─ Read relevant source files                                  │
│  ├─ Generate code changes (diff format)                         │
│  ├─ Run tests locally                                           │
│  └─ Create CodeFix record with changes                          │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    PR PHASE                                      │
│  (PlatformEvolution::PullRequestJob - triggered by code fix)    │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ GitHubPRService.create_pr(code_fix)                              │
│  ├─ Create branch                                               │
│  ├─ Apply changes                                               │
│  ├─ Create PR with description                                  │
│  └─ Create PullRequestSubmission record                         │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    HUMAN APPROVAL                                │
│  (Admin reviews PR, approves or requests changes)               │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ Post-Merge                                                       │
│  ├─ SupportTicket marked resolved                               │
│  ├─ DebugSession marked successful                              │
│  └─ Learning archived to GlobalKnowledgeArchive                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5. Agent Learning Flow (Agent Lightning)
```
┌─────────────────────────────────────────────────────────────────┐
│                    TRACE COLLECTION                              │
│  (During every agent execution)                                  │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ AgentPluginExecution creates:                                    │
│  ├─ AgentLLMCall records (every LLM interaction)                │
│  ├─ AgentToolExecution records (every tool use)                 │
│  ├─ AgentPhaseExecution records (workflow phases)               │
│  └─ AgentLightningTrace (summary for training)                  │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    REWARD SIGNAL                                 │
│  (From user feedback, success metrics, or automated scoring)    │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ AgentLightningTrace.update!(                                     │
│   reward_score: calculated_reward,                               │
│   reward_components: { user_feedback, success, efficiency }     │
│ )                                                                │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    TRAINING TRIGGER                              │
│  (AgentLightningTrainingService.run_training_if_ready)          │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ Checks:                                                          │
│  ├─ config.enabled?                                             │
│  ├─ config.should_retrain? (time since last training)           │
│  └─ traces.count >= config.min_traces_for_training              │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    PYTHON RL SERVICE                             │
│  (PythonAgentLightningClient)                                   │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ Training Process:                                                │
│  ├─ Send trace data to Python service                           │
│  ├─ RL optimization (PPO/DPO)                                   │
│  ├─ Generate optimized prompts                                  │
│  └─ Return improvements                                         │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ AgentLightningOptimization.create!(                              │
│   agent_plugin: agent,                                           │
│   optimization_type: 'prompt_improvement',                       │
│   old_value: original_prompt,                                    │
│   new_value: optimized_prompt,                                   │
│   improvement_score: calculated_improvement                      │
│ )                                                                │
└─────────────────────────────────────────────────────────────────┘
```

### 6. Agent Collaboration Flow
```
┌─────────────────────────────────────────────────────────────────┐
│ Agent A needs help from Agent B                                  │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ AskAgentForHelpTool.execute({                                    │
│   request_type: 'subtask',                                       │
│   description: 'Analyze customer data',                          │
│   helper_agent_slug: 'analytics_agent'  # optional              │
│ })                                                               │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ Energy Check                                                     │
│  ├─ Agent A has enough energy? (based on request_type cost)     │
│  └─ If not, check CommunityEnergyPool for loan                  │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ Helper Selection (if not specified)                              │
│  ├─ IrreplaceabilityAwareRouter.route_task()                    │
│  ├─ Consider: capability beliefs, relationships, energy         │
│  └─ Select best available helper                                │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ AgentCollaborationRequest.create!(                               │
│   requesting_agent: agent_a,                                     │
│   helper_agent: agent_b,                                         │
│   request_type: 'subtask',                                       │
│   description: '...',                                            │
│   energy_cost: 10,                                               │
│   energy_reward: 15                                              │
│ )                                                                │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ Helper Execution                                                 │
│  ├─ request.accept!(helper)                                     │
│  ├─ request.start!                                              │
│  ├─ Helper agent executes subtask                               │
│  └─ request.complete!(response: result)                         │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ Relationship Update                                              │
│  ├─ AgentRelationship.record_collaboration!(outcome)            │
│  ├─ Update trust_score, compatibility_score                     │
│  └─ Track helpfulness_ratings                                   │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ Energy Settlement                                                │
│  ├─ Agent A spends energy (already charged)                     │
│  ├─ Agent B earns reward (with progressive tax)                 │
│  └─ Tax goes to CommunityEnergyPool                             │
└─────────────────────────────────────────────────────────────────┘
```

### 7. Context Graph Flow
```
┌─────────────────────────────────────────────────────────────────┐
│ Agent makes a decision during execution                          │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ DecisionTrace.record_decision!(                                  │
│   entity: entity,                                                │
│   agent_plugin: agent,                                           │
│   decision_type: 'action',                                       │
│   decision_summary: 'Sent email to segment A',                  │
│   reasoning: 'High engagement predicted...',                    │
│   context_gathered: { segment_size: 1500, ... },                │
│   inputs_used: ['contact_data', 'engagement_history'],          │
│   policies_evaluated: ['email_frequency', 'gdpr_compliance'],   │
│   confidence_score: 0.87                                        │
│ )                                                                │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ Callbacks (after_create):                                        │
│  ├─ generate_trace_id (before_validation)                       │
│  ├─ generate_embedding (vector for similarity search)           │
│  └─ find_and_link_precedents!                                   │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ Precedent Search                                                 │
│  ├─ find_similar_decisions(limit: 3, min_similarity: 0.75)      │
│  ├─ Uses pgvector nearest neighbor search                       │
│  └─ Creates DecisionPrecedent links                             │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ For Exceptions:                                                  │
│  ├─ is_exception: true                                          │
│  ├─ exception_justification: 'Customer requested urgency'       │
│  ├─ requires_approval: true                                     │
│  └─ Waits for admin approval before proceeding                  │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ Outcome Recording (later):                                       │
│  ├─ decision.update!(outcome: 'success')                        │
│  ├─ outcome_quality_score: 0.92                                 │
│  └─ Informs future precedent searches                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Integration Points Summary

### Models That Connect Systems

| Model | Connects |
|-------|----------|
| `AgentPlugin` | Everything (29 associations) |
| `AgentPluginExecution` | Agents → Traces → Learning |
| `AgentGoal` | Living Platform → Agents → Tasks |
| `SupportTicket` | Users/AMOS → Evolution Engine |
| `DecisionTrace` | Agents → Context Graph → Precedents |
| `AgentCollaborationRequest` | Agent → Agent |
| `AgentRelationship` | Trust network |
| `EvolutionCycle` | Perception → Goals → Tests → Learning |
| `ScheduledAgentTask` | Time → Agents → Execution |

### Services That Bridge Systems

| Service | Bridges |
|---------|---------|
| `Amos::Orchestrator` | Everything (central brain) |
| `AgentPluginService` | Agents → Execution → Memory |
| `SmartRouterService` | Tasks → Best Agent |
| `ContextGraph::DecisionRecorder` | Execution → Memory |
| `LivingPlatform::EvolutionCycleService` | All Living Platform components |
| `Collaboration::AgentSchool` | Failing agents → Training → Redeployment |

### Jobs That Trigger Integrations

| Job | Triggers |
|-----|----------|
| `PerceptionJob` | → DesireEngineJob |
| `DesireEngineJob` | → Goal execution |
| `EvolutionCycleJob` | → A/B Tests → School |
| `LogMonitorJob` | → DebugAgentJob → CodeFixJob → PullRequestJob |
| `ScheduledTaskDispatcherJob` | → Agent executions |
| `AgentSchoolEnrollmentJob` | → Diagnosis → Training → Graduation |

---

## ⚠️ Gap Analysis

See [gaps-analysis.md](./gaps-analysis.md) for systems that need better integration.


