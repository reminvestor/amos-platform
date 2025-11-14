"""
Agent Lightning Service - FastAPI Application

This service provides RL-based training for AI agents using Microsoft's Agent Lightning library.
It receives trace data from the Rails application and performs training with the VERL algorithm.
"""
import asyncio
import logging
from contextlib import asynccontextmanager
from typing import Dict, Any, Optional
import time

from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.responses import JSONResponse
from pydantic import BaseModel

# Agent Lightning imports (will be installed via requirements.txt)
try:
    from agentlightning import InMemoryLightningStore, LightningStoreServer
    from agentlightning import RolloutConfig
    AGENT_LIGHTNING_AVAILABLE = True
except ImportError:
    AGENT_LIGHTNING_AVAILABLE = False
    print("⚠️  Agent Lightning not installed - running in mock mode")

from config import settings
from store_adapter import RailsStoreAdapter

# Configure logging
logging.basicConfig(
    level=getattr(logging, settings.log_level),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Global store instance
store: Optional[Any] = None
store_server: Optional[Any] = None
training_jobs: Dict[str, Dict[str, Any]] = {}


# Pydantic models for API requests
class RolloutData(BaseModel):
    rollout_id: str
    input: Dict[str, Any]
    metadata: Dict[str, Any]
    status: str = "queuing"


class SpanData(BaseModel):
    rollout_id: str
    attempt_id: str
    span: Dict[str, Any]


class TrainingRequest(BaseModel):
    entity_id: int
    config: Dict[str, Any]
    trace_ids: Optional[list[str]] = None


class HealthResponse(BaseModel):
    status: str
    agent_lightning_available: bool
    store_initialized: bool
    store_server_running: bool
    active_training_jobs: int


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown logic"""
    global store, store_server

    logger.info("🚀 Starting Agent Lightning Service")
    logger.info(f"Configuration: {settings.dict()}")

    # Initialize Store
    if AGENT_LIGHTNING_AVAILABLE:
        try:
            logger.info("Initializing InMemoryLightningStore...")
            store = InMemoryLightningStore()

            logger.info(f"Starting LightningStoreServer on {settings.store_host}:{settings.store_port}...")
            store_server = LightningStoreServer(
                store=store,
                host=settings.store_host,
                port=settings.store_port
            )

            # Start store server in background
            asyncio.create_task(store_server.start())
            logger.info("✅ LightningStoreServer started successfully")

        except Exception as e:
            logger.error(f"❌ Failed to initialize Agent Lightning: {e}")
            raise
    else:
        logger.warning("⚠️  Agent Lightning not available - running in mock mode")

    yield

    # Shutdown logic
    logger.info("🛑 Shutting down Agent Lightning Service")
    if store_server:
        try:
            await store_server.stop()
            logger.info("✅ LightningStoreServer stopped")
        except Exception as e:
            logger.error(f"Error stopping store server: {e}")


# Initialize FastAPI app
app = FastAPI(
    title="Agent Lightning Service",
    description="RL-based training service for AI agents",
    version="1.0.0",
    lifespan=lifespan
)


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint"""
    return HealthResponse(
        status="healthy",
        agent_lightning_available=AGENT_LIGHTNING_AVAILABLE,
        store_initialized=store is not None,
        store_server_running=store_server is not None,
        active_training_jobs=len(training_jobs)
    )


@app.get("/")
async def root():
    """Root endpoint with service information"""
    return {
        "service": "Agent Lightning Service",
        "version": "1.0.0",
        "status": "running",
        "agent_lightning_available": AGENT_LIGHTNING_AVAILABLE,
        "endpoints": {
            "health": "/health",
            "rollouts": "/api/rollouts",
            "spans": "/api/spans",
            "training": "/api/training/*"
        }
    }


@app.post("/api/rollouts")
async def create_rollout(rollout_data: RolloutData):
    """
    Create a new rollout in the Store

    Receives rollout data from Rails and adds it to the Agent Lightning Store
    """
    if not AGENT_LIGHTNING_AVAILABLE or not store:
        raise HTTPException(
            status_code=503,
            detail="Agent Lightning not available"
        )

    try:
        logger.info(f"Creating rollout: {rollout_data.rollout_id}")

        # Create rollout config
        config = RolloutConfig(
            timeout_seconds=settings.rollout_timeout_seconds,
            unresponsive_seconds=settings.unresponsive_timeout_seconds,
            max_attempts=settings.max_attempts
        )

        # Add rollout to store
        await store.create_rollout(
            rollout_id=rollout_data.rollout_id,
            input=rollout_data.input,
            metadata=rollout_data.metadata,
            config=config
        )

        logger.info(f"✅ Rollout created: {rollout_data.rollout_id}")

        return {
            "status": "created",
            "rollout_id": rollout_data.rollout_id
        }

    except Exception as e:
        logger.error(f"❌ Failed to create rollout: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/spans")
async def add_span(span_data: SpanData):
    """
    Add a span to an existing rollout

    Receives span data from Rails and adds it to the Store for the specified rollout/attempt
    """
    if not AGENT_LIGHTNING_AVAILABLE or not store:
        raise HTTPException(
            status_code=503,
            detail="Agent Lightning not available"
        )

    try:
        logger.debug(f"Adding span to rollout {span_data.rollout_id}")

        # Add span to store
        await store.add_span(span_data.span)

        return {"status": "added"}

    except Exception as e:
        logger.error(f"❌ Failed to add span: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/training/start")
async def start_training(
    training_request: TrainingRequest,
    background_tasks: BackgroundTasks
):
    """
    Start a new training job

    Phase 2: Fetches traces from Rails DB using store adapter, converts to rollouts, and starts VERL training
    """
    if not AGENT_LIGHTNING_AVAILABLE or not store:
        raise HTTPException(
            status_code=503,
            detail="Agent Lightning not available"
        )

    try:
        job_id = f"train_{training_request.entity_id}_{int(time.time())}"

        logger.info(f"Starting training job {job_id} for entity {training_request.entity_id}")

        # Store job metadata
        training_jobs[job_id] = {
            "job_id": job_id,
            "entity_id": training_request.entity_id,
            "status": "queued",
            "started_at": time.time(),
            "config": training_request.config
        }

        # Schedule training in background
        # Phase 2: Now uses RailsStoreAdapter to load training data from database
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
            "message": "Training job queued successfully"
        }

    except Exception as e:
        logger.error(f"❌ Failed to start training: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/training/{job_id}/status")
async def get_training_status(job_id: str):
    """Get the status of a training job"""
    if job_id not in training_jobs:
        raise HTTPException(status_code=404, detail="Training job not found")

    return training_jobs[job_id]


@app.get("/api/training/jobs")
async def list_training_jobs():
    """List all training jobs"""
    return {
        "jobs": list(training_jobs.values()),
        "total": len(training_jobs)
    }


async def run_training_job(
    job_id: str,
    entity_id: int,
    config: Dict[str, Any],
    trace_ids: Optional[list[str]] = None
):
    """
    Background task to run training

    Phase 2: Load traces from Rails DB using store adapter
    Phase 3: Span emission is handled in Rails service
    Phase 4: Real VERL training with Agent Lightning Trainer
    """
    adapter = None
    try:
        training_jobs[job_id]["status"] = "running"
        logger.info(f"Running training job {job_id}")

        # Phase 2: Load training data from Rails DB
        adapter = RailsStoreAdapter(settings.database_url)

        try:
            # Populate store with real training data
            result = await adapter.load_traces_for_training(
                entity_id=entity_id,
                trace_ids=trace_ids,
                store=store
            )

            logger.info(f"✅ Loaded training data: {result}")
            training_jobs[job_id]["data_loaded"] = result

        except Exception as e:
            logger.error(f"Failed to load training data from database: {e}")
            # Continue anyway - we'll train with empty store
            training_jobs[job_id]["data_loaded"] = {
                "success": False,
                "error": str(e)
            }

        # Phase 4: Real VERL Training with Agent Lightning
        if store and AGENT_LIGHTNING_AVAILABLE:
            logger.info(f"Starting Phase 4: Real VERL training...")
            training_result = await run_real_training(job_id, entity_id, config)
            training_jobs[job_id]["results"] = training_result
        else:
            logger.warning("Agent Lightning not available - skipping real training")
            # Simulate training for testing
            await asyncio.sleep(2)
            training_jobs[job_id]["results"] = {
                "message": "Training simulation (Agent Lightning unavailable)",
                "entity_id": entity_id
            }

        training_jobs[job_id]["status"] = "completed"
        training_jobs[job_id]["completed_at"] = time.time()
        logger.info(f"✅ Training job {job_id} completed")

    except Exception as e:
        logger.error(f"❌ Training job {job_id} failed: {e}")
        training_jobs[job_id]["status"] = "failed"
        training_jobs[job_id]["error"] = str(e)

    finally:
        if adapter:
            await adapter.disconnect()


async def run_real_training(job_id: str, entity_id: int, config: Dict[str, Any]) -> Dict[str, Any]:
    """
    Phase 4: Execute real Agent Lightning VERL training

    Trains on loaded store data, extracts optimized prompts, and calculates improvements
    """
    try:
        logger.info(f"🚀 Initializing VERL Trainer for job {job_id}")

        from agentlightning import Trainer, TrainerConfig

        # Configure trainer with provided settings
        trainer_config = TrainerConfig(
            n_runners=config.get('n_runners', settings.n_runners),
            execution_strategy=settings.execution_strategy,
            learning_rate=config.get('learning_rate', settings.default_learning_rate),
            batch_size=config.get('batch_size', settings.default_batch_size),
            num_epochs=config.get('num_epochs', settings.default_epochs),
            checkpoint_dir=settings.checkpoint_dir
        )

        trainer = Trainer(
            store=store,
            config=trainer_config
        )

        logger.info(f"Training Trainer initialized. Starting training...")

        # Run actual training
        training_result = await trainer.train()

        logger.info(f"✅ VERL training completed")

        # Extract optimized prompts and improvements
        optimized_prompts = await extract_optimized_prompts(training_result)
        improvement = calculate_improvement(training_result)

        return {
            "status": "completed",
            "overall_improvement": improvement,
            "optimized_prompts": optimized_prompts,
            "training_metrics": training_result.metrics if hasattr(training_result, 'metrics') else {}
        }

    except Exception as e:
        logger.error(f"Real training failed: {e}")
        return {
            "status": "failed",
            "error": str(e)
        }


async def extract_optimized_prompts(training_result) -> Dict[str, Any]:
    """
    Phase 4: Extract optimized prompts from training results

    Maps Agent Lightning patterns to workflow phase improvements
    """
    optimized_prompts = {}

    try:
        if hasattr(training_result, 'optimized_patterns'):
            for pattern in training_result.optimized_patterns:
                prompt_key = getattr(pattern, 'context_type', 'general')

                optimized_prompts[prompt_key] = {
                    'original': getattr(pattern, 'original_prompt', ''),
                    'optimized': getattr(pattern, 'optimized_prompt', ''),
                    'improvement': getattr(pattern, 'improvement_score', 0),
                    'examples': getattr(pattern, 'successful_examples', [])
                }

        logger.info(f"Extracted {len(optimized_prompts)} optimized prompts")

    except Exception as e:
        logger.warning(f"Could not extract optimized prompts: {e}")

    return optimized_prompts


def calculate_improvement(training_result) -> float:
    """
    Phase 4: Calculate overall improvement percentage from training metrics
    """
    try:
        baseline_metrics = getattr(training_result, 'baseline_metrics', {})
        optimized_metrics = getattr(training_result, 'optimized_metrics', {})

        if not baseline_metrics or not optimized_metrics:
            return 0

        improvements = []

        # Success rate improvement
        if baseline_metrics.get('success_rate') and optimized_metrics.get('success_rate'):
            success_improvement = (
                (optimized_metrics['success_rate'] - baseline_metrics['success_rate'])
                / baseline_metrics['success_rate'] * 100
            )
            improvements.append(success_improvement)

        # Cost improvement
        if baseline_metrics.get('avg_cost') and optimized_metrics.get('avg_cost'):
            cost_improvement = (
                (baseline_metrics['avg_cost'] - optimized_metrics['avg_cost'])
                / baseline_metrics['avg_cost'] * 100
            )
            improvements.append(cost_improvement)

        # Latency improvement
        if baseline_metrics.get('avg_latency') and optimized_metrics.get('avg_latency'):
            latency_improvement = (
                (baseline_metrics['avg_latency'] - optimized_metrics['avg_latency'])
                / baseline_metrics['avg_latency'] * 100
            )
            improvements.append(latency_improvement)

        if improvements:
            overall = sum(improvements) / len(improvements)
            logger.info(f"Training improvements: {overall:.2f}%")
            return overall
        else:
            return 0

    except Exception as e:
        logger.warning(f"Could not calculate improvement: {e}")
        return 0


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app:app",
        host=settings.api_host,
        port=settings.api_port,
        reload=settings.debug,
        log_level=settings.log_level.lower()
    )
