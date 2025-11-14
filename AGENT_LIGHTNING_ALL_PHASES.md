# Agent Lightning - Complete Implementation Guide (Phases 2-6)

## Phase 1 Status: ✅ COMPLETE

- Python FastAPI service running (port 4747)
- LightningStoreServer running (port 4748)
- InMemoryLightningStore initialized
- Rails client communicates with Python
- Docker Compose configured
- Mock training endpoint working

---

# PHASE 2: Store Adapter (Database → Agent Lightning)

**Goal:** Connect Rails PostgreSQL database to Agent Lightning's InMemoryLightningStore

## What to Build

### File 1: `python_services/agent_lightning/models.py`

Pydantic models for Rails database records:

```python
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from datetime import datetime

class RailsTrace(BaseModel):
    """Maps to agent_lightning_traces table"""
    id: int
    entity_id: int
    trace_id: str
    workflow_execution_id: Optional[int]
    workflow_type: Optional[str]
    user_goal: Optional[str]
    status: str
    reward_signal: Optional[float]
    success_rate: Optional[float]
    cost_efficiency_score: Optional[float]
    user_rating: Optional[int]
    token_count: Optional[int]
    cost_estimate: Optional[float]
    duration_ms: Optional[int]
    created_at: datetime
    metadata: Optional[Dict[str, Any]] = {}

class RailsLlmCall(BaseModel):
    """Maps to agent_llm_calls table"""
    id: int
    trace_id: str
    model_id: str
    purpose: Optional[str]
    input_tokens: int
    output_tokens: int
    total_tokens: int
    cost_estimate: float
    latency_ms: int
    status: str
    prompt_preview: Optional[str]
    response_preview: Optional[str]
    called_at: datetime
    metadata: Optional[Dict[str, Any]] = {}

class RailsToolExecution(BaseModel):
    """Maps to agent_tool_executions table"""
    id: int
    trace_id: str
    tool_name: str
    status: str
    duration_ms: Optional[int]
    started_at: datetime
    completed_at: Optional[datetime]
    error_message: Optional[str]
```

### File 2: `python_services/agent_lightning/store_adapter.py`

Main adapter class:

```python
import asyncpg
from typing import List, Dict, Any, Optional
from datetime import datetime
import logging
from .models import RailsTrace, RailsLlmCall, RailsToolExecution

logger = logging.getLogger(__name__)

class RailsStoreAdapter:
    """Adapter to read training data from Rails PostgreSQL and populate Agent Lightning store"""

    def __init__(self, database_url: str):
        self.database_url = database_url
        self.conn = None

    async def connect(self):
        """Establish database connection"""
        if not self.conn:
            self.conn = await asyncpg.connect(self.database_url)
        return self.conn

    async def disconnect(self):
        """Close database connection"""
        if self.conn:
            await self.conn.close()
            self.conn = None

    async def load_traces_for_training(
        self,
        entity_id: int,
        trace_ids: List[str],
        store: Any
    ) -> Dict[str, Any]:
        """Load specified traces from Rails DB and populate Agent Lightning store"""

        await self.connect()

        try:
            # Fetch traces
            traces = await self._fetch_traces(entity_id, trace_ids)
            logger.info(f"Loaded {len(traces)} traces for entity {entity_id}")

            rollouts_created = 0
            spans_created = 0

            for trace_data in traces:
                trace = RailsTrace(**trace_data)

                # Convert trace to rollout
                rollout = await self._create_rollout(trace, store)
                rollouts_created += 1

                # Fetch and add LLM calls as spans
                llm_calls = await self._fetch_llm_calls(trace.trace_id)
                for llm_call_data in llm_calls:
                    llm_call = RailsLlmCall(**llm_call_data)
                    span = await self._create_span(trace.trace_id, 0, llm_call)
                    store.add_span(trace.trace_id, 0, span)
                    spans_created += 1

                # Fetch and add tool executions as spans
                tool_execs = await self._fetch_tool_executions(trace.trace_id)
                for tool_data in tool_execs:
                    tool = RailsToolExecution(**tool_data)
                    span = await self._create_tool_span(trace.trace_id, 0, tool)
                    store.add_span(trace.trace_id, 0, span)
                    spans_created += 1

            logger.info(f"Created {rollouts_created} rollouts with {spans_created} spans")

            return {
                "success": True,
                "rollouts_created": rollouts_created,
                "spans_created": spans_created,
                "traces_loaded": len(traces)
            }

        except Exception as e:
            logger.error(f"Failed to load traces: {e}")
            raise

    async def _fetch_traces(self, entity_id: int, trace_ids: List[str]) -> List[Dict]:
        """Fetch traces from database"""
        query = """
            SELECT *
            FROM agent_lightning_traces
            WHERE entity_id = $1
              AND trace_id = ANY($2)
              AND status = 'completed'
              AND reward_signal IS NOT NULL
            ORDER BY created_at DESC
        """
        rows = await self.conn.fetch(query, entity_id, trace_ids)
        return [dict(row) for row in rows]

    async def _fetch_llm_calls(self, trace_id: str) -> List[Dict]:
        """Fetch LLM calls for a trace"""
        query = """
            SELECT *
            FROM agent_llm_calls
            WHERE trace_id = $1
            ORDER BY called_at ASC
        """
        rows = await self.conn.fetch(query, trace_id)
        return [dict(row) for row in rows]

    async def _fetch_tool_executions(self, trace_id: str) -> List[Dict]:
        """Fetch tool executions for a trace"""
        query = """
            SELECT *
            FROM agent_tool_executions
            WHERE trace_id = $1
            ORDER BY started_at ASC
        """
        rows = await self.conn.fetch(query, trace_id)
        return [dict(row) for row in rows]

    async def _create_rollout(self, trace: RailsTrace, store: Any):
        """Convert Rails trace to Agent Lightning rollout"""
        from agentlightning import RolloutConfig

        config = RolloutConfig(
            rollout_id=trace.trace_id,
            metadata={
                "entity_id": trace.entity_id,
                "workflow_type": trace.workflow_type,
                "workflow_id": trace.workflow_execution_id,
                "user_goal": trace.user_goal,
                "success_rate": trace.success_rate,
                "cost": trace.cost_estimate,
                "tokens": trace.token_count
            }
        )

        rollout = store.create_rollout(config)

        # Add reward signal
        if trace.reward_signal is not None:
            rollout.reward = trace.reward_signal

        return rollout

    async def _create_span(self, rollout_id: str, attempt_id: int, llm_call: RailsLlmCall):
        """Convert Rails LLM call to Agent Lightning span"""
        from agentlightning import Span

        return Span(
            name=llm_call.purpose or "llm_call",
            start_time=llm_call.called_at.timestamp(),
            end_time=llm_call.called_at.timestamp() + (llm_call.latency_ms / 1000.0),
            status=llm_call.status,
            metadata={
                "type": "llm_call",
                "model": llm_call.model_id,
                "input_tokens": llm_call.input_tokens,
                "output_tokens": llm_call.output_tokens,
                "cost": llm_call.cost_estimate,
                "prompt_preview": llm_call.prompt_preview,
                "response_preview": llm_call.response_preview
            }
        )

    async def _create_tool_span(self, rollout_id: str, attempt_id: int, tool: RailsToolExecution):
        """Convert Rails tool execution to Agent Lightning span"""
        from agentlightning import Span

        end_time = tool.completed_at.timestamp() if tool.completed_at else tool.started_at.timestamp()

        return Span(
            name=f"tool:{tool.tool_name}",
            start_time=tool.started_at.timestamp(),
            end_time=end_time,
            status=tool.status,
            metadata={
                "type": "tool_execution",
                "tool_name": tool.tool_name,
                "duration_ms": tool.duration_ms,
                "error": tool.error_message
            }
        )
```

### File 3: Update `python_services/agent_lightning/app.py`

Modify training endpoint to use adapter:

```python
# Add import at top
from .store_adapter import RailsStoreAdapter

# Update /api/training/start endpoint
@app.post("/api/training/start")
async def start_training(
    training_request: TrainingRequest,
    background_tasks: BackgroundTasks
):
    job_id = f"train_{training_request.entity_id}_{int(time.time())}"

    # NEW: Load training data from Rails DB
    adapter = RailsStoreAdapter(settings.database_url)

    try:
        # Populate store with real training data
        result = await adapter.load_traces_for_training(
            entity_id=training_request.entity_id,
            trace_ids=training_request.trace_ids,
            store=store
        )

        logger.info(f"Loaded training data: {result}")

        # Schedule training job
        background_tasks.add_task(
            run_training_job,
            job_id,
            training_request.entity_id,
            training_request.config,
            training_request.trace_ids
        )

        return {
            "status": "started",
            "job_id": job_id,
            "data_loaded": result
        }

    except Exception as e:
        logger.error(f"Failed to start training: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        await adapter.disconnect()
```

### Testing Phase 2

```bash
# Check health with store stats
curl http://localhost:4747/health

# Trigger training from Rails
rails console
> entity = Entity.first
> service = AgentLightningTrainingService.new(entity)
> service.execute_training

# Verify store has data
curl http://localhost:4747/api/debug/store-stats
```

---

# PHASE 3: Real-time Span Emission

**Goal:** Update Rails to emit spans to Agent Lightning during workflow execution (not just from historical data)

## What to Build

### Update `app/services/lightning_store_service.rb`

Add real-time span emission:

```ruby
class LightningStoreService
  # NEW: Emit span in real-time to Python service
  def emit_span(rollout_id:, attempt_id:, span_data:)
    return unless agent_lightning_enabled?

    PythonAgentLightningClient.add_span(
      rollout_id,
      attempt_id,
      span_data
    )
  end

  # Update record_llm_call to emit spans
  def record_llm_call(trace_id:, model:, **options)
    # ... existing code to save to DB ...

    # NEW: Emit to Agent Lightning store in real-time
    emit_span(
      rollout_id: trace_id,
      attempt_id: 0,
      span_data: {
        name: options[:purpose] || "llm_call",
        type: "llm_call",
        model: model,
        tokens: {
          input: options[:input_tokens],
          output: options[:output_tokens]
        },
        cost: options[:cost],
        latency_ms: options[:latency_ms]
      }
    )
  end

  private

  def agent_lightning_enabled?
    ENV['AGENT_LIGHTNING_ENABLED'] == 'true'
  end
end
```

---

# PHASE 4: Real VERL Training

**Goal:** Replace mock training with actual Agent Lightning VERL algorithm

## What to Build

### Update `python_services/agent_lightning/app.py`

Replace mock training function:

```python
async def run_training_job(job_id: str, entity_id: int, config: dict, trace_ids: List[str]):
    """Execute real Agent Lightning training using VERL"""

    job = training_jobs[job_id]

    try:
        job['status'] = 'running'
        job['started_at'] = datetime.now()

        logger.info(f"Starting VERL training for job {job_id}")

        # NEW: Use real Agent Lightning trainer
        from agentlightning import Trainer, TrainerConfig

        trainer_config = TrainerConfig(
            n_runners=config.get('n_runners', 4),
            execution_strategy=settings.execution_strategy,  # 'cs' = client-server
            learning_rate=config.get('learning_rate', 0.001),
            batch_size=config.get('batch_size', 32),
            num_epochs=config.get('num_epochs', 3),
            checkpoint_dir=settings.checkpoint_dir
        )

        trainer = Trainer(
            store=store,
            config=trainer_config
        )

        # Run training
        training_result = await trainer.train()

        # Extract optimized prompts
        optimized_prompts = await extract_optimized_prompts(training_result)

        # Calculate improvement metrics
        improvement = calculate_improvement(training_result)

        job['status'] = 'completed'
        job['completed_at'] = datetime.now()
        job['results'] = {
            'overall_improvement': improvement,
            'optimized_prompts': optimized_prompts,
            'training_metrics': training_result.metrics
        }

        logger.info(f"Training completed: {improvement}% improvement")

    except Exception as e:
        logger.error(f"Training failed: {e}")
        job['status'] = 'failed'
        job['error'] = str(e)


async def extract_optimized_prompts(training_result):
    """Extract optimized prompts from training results"""
    # Agent Lightning provides optimized behavior patterns
    # Convert these to prompt improvements

    optimized_prompts = {}

    for pattern in training_result.optimized_patterns:
        # Map pattern to prompt template
        prompt_key = pattern.context_type  # e.g., "gather_context", "goal_execution"

        optimized_prompts[prompt_key] = {
            'original': pattern.original_prompt,
            'optimized': pattern.optimized_prompt,
            'improvement': pattern.improvement_score,
            'examples': pattern.successful_examples
        }

    return optimized_prompts


def calculate_improvement(training_result):
    """Calculate overall improvement percentage"""
    if not training_result.baseline_metrics:
        return 0

    baseline = training_result.baseline_metrics
    optimized = training_result.optimized_metrics

    improvements = []

    if baseline.get('success_rate'):
        success_improvement = (
            (optimized['success_rate'] - baseline['success_rate'])
            / baseline['success_rate'] * 100
        )
        improvements.append(success_improvement)

    if baseline.get('avg_cost'):
        cost_improvement = (
            (baseline['avg_cost'] - optimized['avg_cost'])
            / baseline['avg_cost'] * 100
        )
        improvements.append(cost_improvement)

    return sum(improvements) / len(improvements) if improvements else 0
```

---

# PHASE 5: Production Deployment

**Goal:** Add monitoring, error recovery, and production hardening

## What to Build

### 1. Add Health Monitoring

Update `python_services/agent_lightning/app.py`:

```python
@app.get("/health")
async def health_check():
    """Enhanced health check with diagnostics"""

    db_healthy = False
    try:
        adapter = RailsStoreAdapter(settings.database_url)
        await adapter.connect()
        await adapter.disconnect()
        db_healthy = True
    except:
        pass

    return {
        "status": "healthy" if db_healthy else "degraded",
        "agent_lightning_available": AGENT_LIGHTNING_AVAILABLE,
        "store_initialized": store is not None,
        "store_server_running": store_server is not None,
        "active_training_jobs": len([j for j in training_jobs.values() if j['status'] == 'running']),
        "database_connected": db_healthy,
        "rollouts_in_store": len(store.rollouts) if store else 0,
        "disk_space_mb": get_disk_space(),
        "uptime_seconds": time.time() - startup_time
    }


@app.get("/metrics")
async def get_metrics():
    """Prometheus-style metrics"""

    total_jobs = len(training_jobs)
    completed = len([j for j in training_jobs.values() if j['status'] == 'completed'])
    failed = len([j for j in training_jobs.values() if j['status'] == 'failed'])

    return {
        "training_jobs_total": total_jobs,
        "training_jobs_completed": completed,
        "training_jobs_failed": failed,
        "training_jobs_running": total_jobs - completed - failed,
        "store_rollouts_total": len(store.rollouts) if store else 0
    }
```

### 2. Add Error Recovery

```python
async def run_training_job_with_retry(job_id: str, entity_id: int, config: dict, trace_ids: List[str]):
    """Training with automatic retry on failure"""

    max_retries = 3
    retry_count = 0

    while retry_count < max_retries:
        try:
            await run_training_job(job_id, entity_id, config, trace_ids)
            return  # Success

        except Exception as e:
            retry_count += 1
            logger.warning(f"Training attempt {retry_count} failed: {e}")

            if retry_count >= max_retries:
                logger.error(f"Training failed after {max_retries} attempts")
                training_jobs[job_id]['status'] = 'failed'
                training_jobs[job_id]['error'] = f"Failed after {max_retries} retries: {e}"
                raise

            # Exponential backoff
            await asyncio.sleep(2 ** retry_count)
```

### 3. Add Logging

```python
import logging
import sys

# Configure logging
logging.basicConfig(
    level=settings.log_level,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('/app/logs/agent_lightning.log')
    ]
)
```

---

# PHASE 6: Prompt Optimization Application

**Goal:** Apply optimized prompts back to Rails workflow templates

## What to Build

### 1. Add endpoint to retrieve optimized prompts

`python_services/agent_lightning/app.py`:

```python
@app.get("/api/training/{job_id}/prompts")
async def get_optimized_prompts(job_id: str):
    """Get optimized prompts from a completed training job"""

    job = training_jobs.get(job_id)

    if not job:
        raise HTTPException(status_code=404, detail="Job not found")

    if job['status'] != 'completed':
        raise HTTPException(status_code=400, detail="Job not completed yet")

    return {
        "job_id": job_id,
        "optimized_prompts": job['results'].get('optimized_prompts', {}),
        "improvement": job['results'].get('overall_improvement', 0)
    }
```

### 2. Create Rails service to apply prompts

`app/services/agent_lightning_prompt_optimizer.rb`:

```ruby
class AgentLightningPromptOptimizer
  attr_reader :entity

  def initialize(entity)
    @entity = entity
  end

  # Apply optimized prompts from training job
  def apply_optimizations(job_id)
    # Get optimized prompts from Python service
    result = PythonAgentLightningClient.get_optimized_prompts(job_id)

    optimized_prompts = result['optimized_prompts']
    improvement = result['improvement']

    Rails.logger.info "Applying prompt optimizations with #{improvement}% improvement"

    # Update workflow templates
    optimized_prompts.each do |context_type, prompt_data|
      apply_to_workflow_template(context_type, prompt_data)
    end

    # Create optimization record
    AgentLightningOptimization.create!(
      entity: @entity,
      training_job_id: job_id,
      improvement_percentage: improvement,
      prompts_optimized: optimized_prompts.keys,
      applied_at: Time.current
    )
  end

  private

  def apply_to_workflow_template(context_type, prompt_data)
    # Map context type to workflow phase
    phase = map_context_to_phase(context_type)

    # Find workflows using this phase
    workflows = find_workflows_with_phase(phase)

    workflows.each do |workflow|
      # Update phase instructions
      update_phase_instructions(workflow, phase, prompt_data['optimized'])

      Rails.logger.info "Updated #{workflow.name} - #{phase} phase"
    end
  end

  def map_context_to_phase(context_type)
    {
      'gather_context' => 'gather_context',
      'goal_execution' => 'execute_goal',
      'validation' => 'validate_result'
    }[context_type]
  end

  def find_workflows_with_phase(phase)
    # Load all V2 workflow templates
    Dir.glob(Rails.root.join('app/workflow_templates/*_v2.yml')).map do |file|
      YAML.load_file(file)
    end.select do |workflow|
      workflow['phases']&.key?(phase)
    end
  end

  def update_phase_instructions(workflow, phase, optimized_prompt)
    # Update the phase instructions with optimized prompt
    # This could update YAML files or database records

    workflow['phases'][phase]['instructions'] = optimized_prompt

    # Save updated workflow
    # (Implementation depends on whether templates are in YAML or DB)
  end
end
```

### 3. Add migration for optimization tracking

```bash
rails g migration CreateAgentLightningOptimizations
```

```ruby
class CreateAgentLightningOptimizations < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_lightning_optimizations do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :training_job_id, null: false
      t.decimal :improvement_percentage, precision: 5, scale: 2
      t.jsonb :prompts_optimized, default: []
      t.jsonb :before_prompts, default: {}
      t.jsonb :after_prompts, default: {}
      t.datetime :applied_at
      t.timestamps
    end

    add_index :agent_lightning_optimizations, :training_job_id
    add_index :agent_lightning_optimizations, [:entity_id, :applied_at]
  end
end
```

---

# COMPLETE IMPLEMENTATION PLAN

## Summary of All Phases

**Phase 2:** Database adapter - Load historical traces into store
**Phase 3:** Real-time spans - Emit spans during workflow execution
**Phase 4:** Real VERL - Replace mock with actual RL training
**Phase 5:** Production - Monitoring, error recovery, logging
**Phase 6:** Optimization - Apply optimized prompts to workflows

## Success Criteria

- [ ] Phase 2: Store contains real training data from PostgreSQL
- [ ] Phase 3: Spans appear in store during workflow execution
- [ ] Phase 4: VERL training produces real improvements
- [ ] Phase 5: System runs reliably in production with monitoring
- [ ] Phase 6: Optimized prompts automatically improve workflows

## Estimated Timeline

- Phase 2: 3-5 days
- Phase 3: 2-3 days
- Phase 4: 5-7 days
- Phase 5: 3-4 days
- Phase 6: 3-5 days

**Total: 16-24 days for complete implementation**

## How to Execute on Mobile

Simply tell Claude Code on mobile:

**"Implement all remaining phases (2-6) of Agent Lightning integration. Follow the complete implementation guide in AGENT_LIGHTNING_ALL_PHASES.md. Work through each phase systematically, ensuring each phase works before moving to the next."**
