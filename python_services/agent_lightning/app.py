"""
Agent Lightning Service - FastAPI Application

This service provides RL-based training for AI agents using Microsoft's Agent Lightning library.
It receives trace data from the Rails application and performs training with the VERL algorithm.
"""
import asyncio
import logging
import os
import shutil
from contextlib import asynccontextmanager
from typing import Dict, Any, Optional
import time
from datetime import datetime

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

# Phase 5: Startup time for uptime tracking
startup_time: float = time.time()

# Phase 5: Metrics tracking
metrics_data: Dict[str, Any] = {
    "total_training_jobs": 0,
    "completed_jobs": 0,
    "failed_jobs": 0,
    "total_rollouts_created": 0,
    "total_spans_added": 0,
    "total_api_errors": 0
}


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


@app.get("/health")
async def health_check():
    """
    Phase 5: Enhanced health check with diagnostics

    Returns detailed health information for monitoring
    """
    # Check database connectivity (Phase 5 diagnostic)
    db_healthy = False
    db_error = None
    try:
        adapter = RailsStoreAdapter(settings.database_url)
        await adapter.connect()
        await adapter.disconnect()
        db_healthy = True
    except Exception as e:
        db_error = str(e)
        logger.warn(f"Database health check failed: {e}")

    # Get disk space (Phase 5 monitoring)
    try:
        stat = shutil.disk_usage(settings.checkpoint_dir)
        disk_available_mb = stat.free / (1024 * 1024)
    except Exception as e:
        disk_available_mb = 0
        logger.warn(f"Could not check disk space: {e}")

    # Overall status
    overall_status = "healthy"
    if not db_healthy:
        overall_status = "degraded"
    if not AGENT_LIGHTNING_AVAILABLE:
        overall_status = "degraded"

    return {
        "status": overall_status,
        "timestamp": datetime.now().isoformat(),
        "uptime_seconds": time.time() - startup_time,
        "agent_lightning_available": AGENT_LIGHTNING_AVAILABLE,
        "store_initialized": store is not None,
        "store_server_running": store_server is not None,
        "database_connected": db_healthy,
        "database_error": db_error,
        "active_training_jobs": len(training_jobs),
        "running_jobs": len([j for j in training_jobs.values() if j['status'] == 'running']),
        "disk_available_mb": disk_available_mb,
        "rollouts_in_store": len(store.rollouts) if store else 0,
        "metrics": {
            "total_training_jobs": metrics_data["total_training_jobs"],
            "completed_jobs": metrics_data["completed_jobs"],
            "failed_jobs": metrics_data["failed_jobs"],
            "api_errors": metrics_data["total_api_errors"]
        }
    }


@app.get("/metrics")
async def prometheus_metrics():
    """
    Phase 5: Prometheus-style metrics endpoint for monitoring

    Provides metrics suitable for scraping by Prometheus/Grafana
    """
    uptime = time.time() - startup_time
    success_rate = 0
    if metrics_data["total_training_jobs"] > 0:
        success_rate = (metrics_data["completed_jobs"] / metrics_data["total_training_jobs"]) * 100

    return {
        "uptime_seconds": uptime,
        "training_jobs_total": metrics_data["total_training_jobs"],
        "training_jobs_completed": metrics_data["completed_jobs"],
        "training_jobs_failed": metrics_data["failed_jobs"],
        "training_jobs_running": len([j for j in training_jobs.values() if j['status'] == 'running']),
        "training_success_rate_percent": success_rate,
        "store_rollouts_total": len(store.rollouts) if store else 0,
        "api_errors_total": metrics_data["total_api_errors"],
        "agent_lightning_available": AGENT_LIGHTNING_AVAILABLE
    }


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
            "metrics": "/metrics",
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

    Phase 2: Fetches traces from Rails DB using store adapter
    Phase 5: Enhanced error handling and metrics tracking
    """
    if not AGENT_LIGHTNING_AVAILABLE or not store:
        metrics_data["total_api_errors"] += 1
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

        # Phase 5: Update total training jobs counter
        metrics_data["total_training_jobs"] += 1

        # Schedule training in background with Phase 5 retry logic
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
        metrics_data["total_api_errors"] += 1
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


@app.get("/api/training/{job_id}/optimized-prompts")
async def get_optimized_prompts(job_id: str):
    """
    Phase 6: Get optimized prompts from a completed training job

    Returns the optimized prompts extracted from VERL training results
    so they can be applied back to Rails workflow templates
    """
    job = training_jobs.get(job_id)

    if not job:
        raise HTTPException(status_code=404, detail="Training job not found")

    if job['status'] != 'completed':
        raise HTTPException(
            status_code=400,
            detail=f"Job is {job['status']}, not completed yet"
        )

    results = job.get('results', {})

    if results.get('status') == 'failed':
        raise HTTPException(
            status_code=400,
            detail=f"Training job failed: {results.get('error')}"
        )

    return {
        "job_id": job_id,
        "entity_id": job['entity_id'],
        "status": "ready",
        "optimized_prompts": results.get('optimized_prompts', {}),
        "improvement_percentage": results.get('overall_improvement', 0),
        "training_metrics": results.get('training_metrics', {}),
        "completed_at": job.get('completed_at')
    }


async def run_training_job(
    job_id: str,
    entity_id: int,
    config: Dict[str, Any],
    trace_ids: Optional[list[str]] = None
):
    """
    Background task to run training with Phase 5 error recovery

    Phase 2: Load traces from Rails DB using store adapter
    Phase 3: Span emission is handled in Rails service
    Phase 4: Real VERL training with Agent Lightning Trainer
    Phase 5: Automatic retry with exponential backoff
    """
    # Phase 5: Retry logic with exponential backoff
    max_retries = 3
    retry_count = 0

    while retry_count < max_retries:
        adapter = None
        try:
            training_jobs[job_id]["status"] = "running"
            if retry_count > 0:
                logger.info(f"Training job {job_id} - Retry attempt {retry_count}")
            else:
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

            # Phase 5: Update metrics
            metrics_data["completed_jobs"] += 1
            return  # Success

        except Exception as e:
            retry_count += 1
            logger.warning(f"Training job {job_id} failed (attempt {retry_count}/{max_retries}): {e}")

            if retry_count >= max_retries:
                logger.error(f"Training job {job_id} failed after {max_retries} attempts")
                training_jobs[job_id]["status"] = "failed"
                training_jobs[job_id]["error"] = f"Failed after {max_retries} retries: {e}"

                # Phase 5: Update failure metrics
                metrics_data["failed_jobs"] += 1
                return

            # Phase 5: Exponential backoff before retry
            backoff_seconds = 2 ** retry_count
            logger.info(f"Retrying in {backoff_seconds} seconds...")
            await asyncio.sleep(backoff_seconds)

        finally:
            if adapter:
                try:
                    await adapter.disconnect()
                except:
                    pass


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
