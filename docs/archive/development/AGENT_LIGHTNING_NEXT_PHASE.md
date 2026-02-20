# Agent Lightning - Phase 2: Store Adapter

## Current Status

**Phase 1 COMPLETE ✅**
- Python FastAPI service running on port 4747
- LightningStoreServer running on port 4748
- InMemoryLightningStore initialized
- Rails client communicates with Python service
- Docker Compose orchestration configured
- Training endpoint exists (returns mock results currently)

## What You Need to Do: Phase 2

### Goal: Connect Rails Database to Agent Lightning Store

Currently, the Python service has an empty InMemoryLightningStore. Phase 2 creates a "Store Adapter" that reads training data from the Rails PostgreSQL database and feeds it into Agent Lightning's store.

### Files to Create

#### 1. `python_services/agent_lightning/store_adapter.py`

Create a new file that:
- Connects to PostgreSQL database using `asyncpg`
- Reads from `agent_lightning_traces` table
- Converts Rails traces → Agent Lightning Rollout format
- Reads from `agent_llm_calls` table
- Converts LLM calls → Agent Lightning Spans
- Populates the InMemoryLightningStore with real data

**Key Classes:**
```python
class RailsStoreAdapter:
    """Adapter to read training data from Rails PostgreSQL database"""

    async def load_traces_for_training(self, entity_id: int, trace_ids: List[str]):
        """Load specified traces from Rails DB and convert to rollouts"""

    async def convert_trace_to_rollout(self, trace_data: dict):
        """Convert a Rails AgentLightningTrace to Agent Lightning Rollout"""

    async def convert_llm_call_to_span(self, llm_call: dict):
        """Convert a Rails AgentLlmCall to Agent Lightning Span"""
```

**Database Queries You'll Need:**
```sql
-- Get traces for training
SELECT * FROM agent_lightning_traces
WHERE entity_id = $1
  AND trace_id = ANY($2)
  AND status = 'completed'
  AND reward_signal IS NOT NULL;

-- Get LLM calls for a trace
SELECT * FROM agent_llm_calls
WHERE trace_id = $1
ORDER BY called_at ASC;

-- Get tool executions for a trace
SELECT * FROM agent_tool_executions
WHERE trace_id = $1
ORDER BY started_at ASC;
```

#### 2. Update `python_services/agent_lightning/app.py`

Modify the `/api/training/start` endpoint to:
```python
async def start_training(training_request: TrainingRequest, ...):
    # NEW: Use RailsStoreAdapter to load data
    adapter = RailsStoreAdapter(settings.database_url)

    # Load traces from Rails DB into the store
    await adapter.load_traces_for_training(
        entity_id=training_request.entity_id,
        trace_ids=training_request.trace_ids,
        store=store
    )

    # Then run training (still mock for now, that's Phase 4)
    ...
```

### Data Mapping Guide

**Rails AgentLightningTrace → Agent Lightning Rollout:**
```python
{
    "rollout_id": trace.trace_id,
    "workflow_id": trace.workflow_execution_id,
    "created_at": trace.created_at,
    "metadata": {
        "entity_id": trace.entity_id,
        "workflow_type": trace.workflow_type,
        "user_goal": trace.user_goal
    }
}
```

**Rails AgentLlmCall → Agent Lightning Span:**
```python
{
    "span_id": llm_call.id,
    "rollout_id": llm_call.trace_id,
    "attempt_id": llm_call.attempt_number or 0,
    "name": llm_call.purpose or "llm_call",
    "start_time": llm_call.called_at,
    "end_time": llm_call.called_at + (llm_call.latency_ms / 1000),
    "status": llm_call.status,
    "metadata": {
        "model": llm_call.model_id,
        "input_tokens": llm_call.input_tokens,
        "output_tokens": llm_call.output_tokens,
        "cost": llm_call.cost_estimate,
        "prompt": llm_call.prompt_preview,
        "response": llm_call.response_preview
    }
}
```

**Reward Signal:**
```python
# Add reward to the rollout
rollout.reward = trace.reward_signal
rollout.reward_metadata = {
    "success_rate": trace.success_rate,
    "cost_efficiency": trace.cost_efficiency_score,
    "user_rating": trace.user_rating
}
```

### Testing Phase 2

Once you've created the Store Adapter:

1. **Test database connection:**
```python
# Add to app.py health endpoint
adapter = RailsStoreAdapter(settings.database_url)
can_connect = await adapter.test_connection()
```

2. **Test trace loading:**
```bash
# Rails console
entity = Entity.first
traces = entity.agent_lightning_traces.completed.with_reward.limit(5)
trace_ids = traces.pluck(:trace_id)

# Start training to test adapter
service = AgentLightningTrainingService.new(entity)
service.execute_training(traces)
```

3. **Verify store has data:**
```python
# In Python service, add debug endpoint
@app.get("/api/debug/store-stats")
async def get_store_stats():
    return {
        "rollouts_count": len(store.rollouts),
        "total_spans": sum(len(r.spans) for r in store.rollouts.values()),
        "sample_rollout": list(store.rollouts.keys())[:1] if store.rollouts else None
    }
```

### Success Criteria for Phase 2

- [ ] `RailsStoreAdapter` class created
- [ ] Database connection working
- [ ] Traces are read from PostgreSQL
- [ ] Traces converted to Rollout format
- [ ] LLM calls converted to Spans
- [ ] Store populated with real data
- [ ] Debug endpoint shows rollout count > 0
- [ ] Training job runs without errors (still returns mock results, that's OK)

### What Phase 3 Will Add

After Phase 2 works:
- Phase 3: Update Rails to emit spans in real-time during workflow execution
- Phase 4: Replace mock training with real VERL algorithm
- Phase 5: Production deployment and monitoring
- Phase 6: Apply optimized prompts back to Rails

## How to Tell Mobile App to Work on This

Just say:

**"Implement Phase 2 of Agent Lightning integration. Create the Store Adapter to read training data from Rails PostgreSQL database and populate the InMemoryLightningStore. Follow the guide in AGENT_LIGHTNING_NEXT_PHASE.md"**

## Reference Documentation

- [Agent Lightning Store Docs](https://microsoft.github.io/agent-lightning/stable/api/store/)
- [Phase 1 Complete Guide](docs/AGENT_LIGHTNING_PHASE1_COMPLETE.md)
- [Architecture Overview](docs/AGENT_LIGHTNING_REAL_INTEGRATION.md)
- Rails DB Schema: `db/schema.rb` (see `agent_lightning_traces`, `agent_llm_calls`, `agent_tool_executions`)

## Current Python Service Files

- `python_services/agent_lightning/app.py` - FastAPI application
- `python_services/agent_lightning/config.py` - Configuration
- `python_services/agent_lightning/requirements.txt` - Dependencies
- `python_services/agent_lightning/Containerfile` - Container

**You'll add:**
- `python_services/agent_lightning/store_adapter.py` - NEW (main work)
- `python_services/agent_lightning/models.py` - NEW (Pydantic models for Rails data)

## Estimated Time

3-5 days for a complete Phase 2 implementation with testing.
