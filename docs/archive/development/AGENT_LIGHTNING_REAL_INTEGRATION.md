# Agent Lightning Real Integration Plan

## Overview

This document outlines the architecture and implementation plan for integrating Microsoft's Agent Lightning Python library with our Rails application for production-grade RL-based agent training.

## Architecture Decision

**Goal**: Use the actual Microsoft Agent Lightning library with VERL algorithm for true reinforcement learning optimization of our AI agents.

**Approach**: Hybrid architecture with Rails for data collection/UI and Python for training execution.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        Rails Application                         │
│                                                                   │
│  ┌──────────────────┐      ┌──────────────────┐                │
│  │  Scout Controller│      │ Workflow Engine  │                │
│  │  (Agent Execution)│──▶  │  (Phase-based)   │                │
│  └──────────────────┘      └──────────────────┘                │
│           │                          │                           │
│           ▼                          ▼                           │
│  ┌─────────────────────────────────────────┐                   │
│  │    LightningStoreService                 │                   │
│  │    (Trace Collection)                    │                   │
│  └─────────────────────────────────────────┘                   │
│           │                                                      │
│           ▼                                                      │
│  ┌─────────────────────────────────────────┐                   │
│  │    PostgreSQL Database                   │                   │
│  │    - agent_lightning_traces              │                   │
│  │    - agent_llm_calls                     │                   │
│  │    - agent_tool_executions               │                   │
│  │    - agent_rewards                       │                   │
│  └─────────────────────────────────────────┘                   │
│           │                                                      │
└───────────┼──────────────────────────────────────────────────────┘
            │
            │ REST API / gRPC
            ▼
┌─────────────────────────────────────────────────────────────────┐
│              Python Agent Lightning Service                      │
│                                                                   │
│  ┌─────────────────────────────────────────┐                   │
│  │    Store Adapter                         │                   │
│  │    (Rails DB → Lightning Store format)   │                   │
│  └─────────────────────────────────────────┘                   │
│           │                                                      │
│           ▼                                                      │
│  ┌─────────────────────────────────────────┐                   │
│  │    InMemoryLightningStore                │                   │
│  │    - Rollouts (work units)               │                   │
│  │    - Attempts (retry tracking)           │                   │
│  │    - Spans (ordered trace events)        │                   │
│  └─────────────────────────────────────────┘                   │
│           │                                                      │
│           ▼                                                      │
│  ┌─────────────────────────────────────────┐                   │
│  │    Trainer                               │                   │
│  │    - Task queue orchestration            │                   │
│  │    - Concurrent runners (N workers)      │                   │
│  │    - VERL algorithm integration          │                   │
│  └─────────────────────────────────────────┘                   │
│           │                                                      │
│           ▼                                                      │
│  ┌─────────────────────────────────────────┐                   │
│  │    VERL RL Algorithm                     │                   │
│  │    - Policy gradient computation         │                   │
│  │    - Model weight updates                │                   │
│  │    - Checkpoint management               │                   │
│  └─────────────────────────────────────────┘                   │
│           │                                                      │
│           ▼                                                      │
│    Optimized Agent Prompts / Policies                           │
│           │                                                      │
└───────────┼──────────────────────────────────────────────────────┘
            │
            │ Results API
            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Rails Application                             │
│    Apply optimized prompts to agent configurations              │
└─────────────────────────────────────────────────────────────────┘
```

## Component Breakdown

### 1. Rails Side (Data Collection)

**Keep existing infrastructure**, add Store format compatibility:

#### LightningStoreService Updates
- Add `emit_span()` method to emit frequent heartbeat spans
- Implement rollout/attempt/span hierarchy mapping
- Add monotonic sequence ID generation
- Track state machine: `queuing` → `preparing` → `running` → `succeeded`/`failed`

#### New: RolloutManager
```ruby
class RolloutManager
  # Maps WorkflowExecution → Agent Lightning Rollout
  def create_rollout(workflow_execution, task_session, request_text)
    rollout = {
      rollout_id: SecureRandom.uuid,
      status: "queuing",
      input: { request_text: request_text },
      metadata: { workflow_id: workflow_execution.id },
      created_at: Time.current.to_i
    }

    # Store in PostgreSQL for persistence
    AgentLightningTrace.create!(...)

    # Send to Python service for Store ingestion
    PythonAgentLightningClient.create_rollout(rollout)
  end

  def start_attempt(rollout_id)
    # Create new attempt
    # Send to Python service
  end

  def emit_span(rollout_id, attempt_id, span_data)
    # Emit span with monotonic sequence ID
    # Serves as heartbeat + trace event
  end
end
```

#### New: PythonAgentLightningClient
```ruby
class PythonAgentLightningClient
  BASE_URL = ENV['AGENT_LIGHTNING_SERVICE_URL'] || 'http://localhost:4747'

  def self.create_rollout(rollout_data)
    HTTParty.post("#{BASE_URL}/api/rollouts", body: rollout_data.to_json)
  end

  def self.start_training(entity_id, config)
    HTTParty.post("#{BASE_URL}/api/training/start", body: {
      entity_id: entity_id,
      config: config
    }.to_json)
  end

  def self.get_training_status(job_id)
    HTTParty.get("#{BASE_URL}/api/training/#{job_id}/status")
  end

  def self.get_optimized_prompts(entity_id)
    HTTParty.get("#{BASE_URL}/api/prompts/optimized/#{entity_id}")
  end
end
```

### 2. Python Side (Training Service)

**New Python microservice** with Agent Lightning library:

#### File: `python_services/agent_lightning/app.py`
```python
from fastapi import FastAPI, HTTPException
from agentlightning import InMemoryLightningStore, LightningStoreServer, Trainer
import asyncio
from typing import Dict, Any

app = FastAPI()
store = InMemoryLightningStore()

# Store server for client access
store_server = None

@app.on_event("startup")
async def startup():
    global store_server
    store_server = LightningStoreServer(store=store, host="0.0.0.0", port=4748)
    asyncio.create_task(store_server.start())

@app.post("/api/rollouts")
async def create_rollout(rollout_data: Dict[str, Any]):
    """Receive rollout from Rails, add to Store"""
    rollout_id = rollout_data['rollout_id']

    # Convert Rails format → Agent Lightning Rollout
    await store.create_rollout(
        rollout_id=rollout_id,
        input=rollout_data['input'],
        metadata=rollout_data['metadata'],
        config=RolloutConfig(
            timeout_seconds=600,
            unresponsive_seconds=120,
            max_attempts=3
        )
    )

    return {"status": "created", "rollout_id": rollout_id}

@app.post("/api/spans")
async def add_span(span_data: Dict[str, Any]):
    """Receive span from Rails, add to Store"""
    await store.add_span(span_data)
    return {"status": "added"}

@app.post("/api/training/start")
async def start_training(training_request: Dict[str, Any]):
    """Start RL training with VERL algorithm"""
    entity_id = training_request['entity_id']
    config = training_request['config']

    # Fetch rollouts from Store for this entity
    rollouts = await fetch_entity_rollouts(entity_id)

    # Initialize Trainer with VERL
    trainer = Trainer(
        store=store,
        algorithm="verl",
        n_runners=4,  # Concurrent workers
        adapter=".*",  # Match all agent spans
        training_config={
            "learning_rate": config.get('learning_rate', 0.001),
            "batch_size": config.get('batch_size', 32),
            "total_epochs": config.get('num_epochs', 3)
        }
    )

    # Run training
    job_id = f"train_{entity_id}_{int(time.time())}"
    asyncio.create_task(run_training(trainer, rollouts, job_id))

    return {"status": "started", "job_id": job_id}

async def run_training(trainer, rollouts, job_id):
    """Background task to run training"""
    try:
        results = await trainer.train(rollouts)

        # Store results back to Rails
        await notify_rails_training_complete(job_id, results)
    except Exception as e:
        await notify_rails_training_failed(job_id, str(e))
```

#### File: `python_services/agent_lightning/store_adapter.py`
```python
"""Adapter to convert Rails PostgreSQL data → Agent Lightning Store format"""

import asyncpg
from typing import List, Dict
from agentlightning import Rollout, Attempt, Span

class RailsStoreAdapter:
    def __init__(self, database_url: str):
        self.database_url = database_url

    async def fetch_traces(self, entity_id: int, limit: int = 1000) -> List[Dict]:
        """Fetch traces from Rails PostgreSQL"""
        conn = await asyncpg.connect(self.database_url)

        traces = await conn.fetch("""
            SELECT
                trace_id,
                trace_type,
                status,
                input_data,
                output_data,
                intermediate_steps,
                reward_signal,
                started_at,
                completed_at,
                duration_ms
            FROM agent_lightning_traces
            WHERE entity_id = $1
              AND status IN ('completed', 'failed')
              AND reward_signal IS NOT NULL
              AND included_in_training = FALSE
            ORDER BY created_at DESC
            LIMIT $2
        """, entity_id, limit)

        await conn.close()
        return [dict(trace) for trace in traces]

    async def convert_to_rollouts(self, traces: List[Dict]) -> List[Rollout]:
        """Convert Rails traces → Agent Lightning Rollouts"""
        rollouts = []

        for trace in traces:
            rollout = Rollout(
                rollout_id=trace['trace_id'],
                input=trace['input_data'],
                metadata={
                    'trace_type': trace['trace_type'],
                    'reward': float(trace['reward_signal'] or 0),
                    'duration_ms': trace['duration_ms']
                },
                status=self.map_status(trace['status']),
                created_at=trace['started_at'].timestamp()
            )

            # Add attempts from intermediate steps
            attempts = self.extract_attempts(trace)
            for attempt in attempts:
                rollout.add_attempt(attempt)

            rollouts.append(rollout)

        return rollouts

    def map_status(self, rails_status: str) -> str:
        """Map Rails status → Agent Lightning status"""
        mapping = {
            'pending': 'queuing',
            'running': 'running',
            'completed': 'succeeded',
            'failed': 'failed',
            'training_ready': 'succeeded'
        }
        return mapping.get(rails_status, 'queuing')

    def extract_attempts(self, trace: Dict) -> List[Attempt]:
        """Extract attempts from intermediate steps"""
        # Rails doesn't explicitly track attempts, so create one from the trace
        return [
            Attempt(
                attempt_id=f"{trace['trace_id']}_1",
                status=self.map_status(trace['status']),
                start_time=trace['started_at'].timestamp(),
                end_time=trace['completed_at'].timestamp() if trace['completed_at'] else None,
                spans=self.extract_spans(trace)
            )
        ]

    def extract_spans(self, trace: Dict) -> List[Span]:
        """Convert intermediate steps → Spans"""
        spans = []

        for idx, step in enumerate(trace.get('intermediate_steps', [])):
            spans.append(Span(
                span_id=f"{trace['trace_id']}_span_{idx}",
                sequence_id=idx,
                name=step.get('step', 'unknown'),
                status=step.get('status', 'success'),
                timestamp=step.get('timestamp', 0),
                attributes=step.get('metadata', {}),
                events=[]
            ))

        return spans
```

### 3. Deployment Strategy

#### Docker Compose Setup

```yaml
# compose.yaml additions
services:
  agent_lightning:
    build: ./python_services/agent_lightning
    ports:
      - "4747:4747"  # API server
      - "4748:4748"  # Store server
    environment:
      - DATABASE_URL=postgresql://user:password@db:5432/agent_marketing_production
      - RAILS_API_URL=http://web:3000
    depends_on:
      - db
    volumes:
      - agent_lightning_checkpoints:/app/checkpoints
    networks:
      - agent_marketing_network

volumes:
  agent_lightning_checkpoints:
```

#### Python Service Containerfile

```dockerfile
# python_services/agent_lightning/Containerfile
FROM python:3.11-slim

WORKDIR /app

# Install Agent Lightning and dependencies
RUN pip install agent-lightning fastapi uvicorn httpx asyncpg

COPY . /app

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "4747"]
```

### 4. Integration Workflow

#### Training Flow

1. **Data Collection** (Rails)
   ```ruby
   # In WorkflowEngine
   lightning_store = LightningStoreService.new(entity, user)
   lightning_store.start_workflow_trace(workflow_execution, task_session, request)

   # Emit spans frequently
   lightning_store.emit_span("Starting gather context phase...")
   lightning_store.emit_span("Executed tool: get_business_profile")

   # Record LLM calls
   lightning_store.record_llm_call(...)

   # Complete with reward
   lightning_store.complete_trace(output_data: result, status: "completed")
   lightning_store.record_reward(reward_type: "completion", reward_value: 0.85)
   ```

2. **Trigger Training** (Rails → Python)
   ```ruby
   # In AgentLightningTrainingService
   def execute_training
     response = PythonAgentLightningClient.start_training(
       entity.id,
       {
         learning_rate: config.learning_parameters['learning_rate'],
         batch_size: config.learning_parameters['batch_size'],
         num_epochs: config.learning_parameters['num_epochs']
       }
     )

     # Poll for completion
     job_id = response['job_id']
     monitor_training_progress(job_id)
   end
   ```

3. **Training Execution** (Python)
   - Fetch traces from Rails DB via adapter
   - Convert to Rollout format
   - Load into InMemoryLightningStore
   - Execute Trainer with VERL algorithm
   - Compute policy gradients
   - Generate optimized prompts

4. **Apply Results** (Python → Rails)
   ```ruby
   # Webhook callback from Python service
   def apply_optimized_prompts(job_id, results)
     optimized_prompts = results['optimized_prompts']

     # Update system prompts in workflow templates
     optimized_prompts.each do |agent_role, prompt|
       update_agent_system_prompt(agent_role, prompt)
     end

     # Mark training job complete
     training_job.mark_completed(results)
   end
   ```

## Implementation Phases

### Phase 1: Python Service Setup (Week 1)
- [ ] Create Python service directory structure
- [ ] Install Agent Lightning library
- [ ] Implement basic FastAPI server
- [ ] Test InMemoryLightningStore locally
- [ ] Create Docker container

### Phase 2: Store Adapter (Week 2)
- [ ] Implement RailsStoreAdapter
- [ ] Add PostgreSQL connection to Python service
- [ ] Test trace → rollout conversion
- [ ] Validate data integrity

### Phase 3: Rails Integration (Week 3)
- [ ] Create PythonAgentLightningClient
- [ ] Update LightningStoreService with span emission
- [ ] Add RolloutManager
- [ ] Test end-to-end data flow

### Phase 4: Trainer Integration (Week 4)
- [ ] Implement training endpoint in Python service
- [ ] Configure VERL algorithm
- [ ] Test with small dataset (Trainer.dev())
- [ ] Add progress monitoring

### Phase 5: Production Deployment (Week 5)
- [ ] Add monitoring and logging
- [ ] Implement checkpoint management
- [ ] Add error recovery
- [ ] Deploy to staging
- [ ] Performance tuning

### Phase 6: Optimization (Week 6)
- [ ] Implement prompt application workflow
- [ ] Add A/B testing for optimized vs baseline
- [ ] Create admin UI for monitoring training
- [ ] Document system

## Configuration

### Environment Variables

```bash
# Rails .env
AGENT_LIGHTNING_SERVICE_URL=http://agent_lightning:4747
AGENT_LIGHTNING_ENABLED=true

# Python service .env
DATABASE_URL=postgresql://user:password@db:5432/agent_marketing_production
RAILS_API_URL=http://web:3000
STORE_PORT=4748
API_PORT=4747
LOG_LEVEL=INFO
```

### AgentLightningConfig Updates

Add to Rails model:

```ruby
# New fields
- python_service_url: string
- verl_learning_rate: decimal
- verl_batch_size: integer
- verl_total_epochs: integer
- n_concurrent_runners: integer
- checkpoint_directory: string
```

## Testing Strategy

### Unit Tests
- RailsStoreAdapter conversion logic
- PythonAgentLightningClient API calls
- Span emission and sequencing

### Integration Tests
- Rails → Python data flow
- Training job lifecycle
- Optimized prompt application

### End-to-End Tests
- Complete workflow with training
- Multi-entity training isolation
- Failure recovery scenarios

## Monitoring

### Metrics to Track
- Training job duration
- Policy improvement percentage
- Checkpoint sizes
- API latency (Rails ↔ Python)
- Store memory usage
- Span throughput

### Logging
- All training jobs with entity_id
- Rollout conversion errors
- VERL algorithm convergence
- Prompt optimization results

## Security Considerations

- [ ] API authentication between Rails and Python
- [ ] Entity data isolation in training
- [ ] Secure checkpoint storage
- [ ] Encrypt sensitive prompt data
- [ ] Rate limiting on training endpoints

## Rollback Plan

If Python integration fails:
1. Disable Python service calls
2. Fall back to Rails-only training
3. Maintain existing prompt system
4. Log errors for debugging

## Success Criteria

- ✅ Training completes successfully with VERL
- ✅ Optimized prompts show measurable improvement
- ✅ System handles 1000+ traces per training run
- ✅ End-to-end latency < 5 minutes for training
- ✅ Zero data loss during conversion
- ✅ Multi-tenant isolation maintained

## Next Steps

1. **Review and approve this architecture**
2. **Set up Python service repository**
3. **Install Agent Lightning library locally**
4. **Create proof-of-concept with 10 sample traces**
5. **Iterate based on learnings**
