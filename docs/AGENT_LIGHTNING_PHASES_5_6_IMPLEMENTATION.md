# Agent Lightning Phases 5 & 6 Implementation Guide

## Overview

This document covers Phases 5 and 6 of the Agent Lightning integration:

- **Phase 5: Production Deployment** - Adds monitoring, error recovery, and operational readiness
- **Phase 6: Prompt Optimization Application** - Closes the RL loop by applying optimized prompts to workflow templates

Together, these phases complete the end-to-end RL-based agent optimization system.

## Phase 5: Production Deployment

### Objective

Make the Agent Lightning training system production-ready with comprehensive monitoring, health checks, error recovery, and metrics collection.

### Components Implemented

#### 1. Enhanced Health Check Endpoint (`/health`)

**Location**: `python_services/agent_lightning/app.py`

The health endpoint now provides comprehensive diagnostics:

```python
@app.get("/health")
async def health_check():
    """Phase 5: Enhanced health check with diagnostics"""
    overall_status = "healthy"

    # Database connectivity check
    db_healthy = await check_database_connection()
    if not db_healthy:
        overall_status = "degraded"

    # Disk space monitoring
    disk_available_mb = check_disk_space()
    if disk_available_mb < 1000:  # Less than 1GB
        overall_status = "degraded"

    return {
        "status": overall_status,
        "timestamp": datetime.now().isoformat(),
        "uptime_seconds": time.time() - startup_time,
        "database_connected": db_healthy,
        "disk_available_mb": disk_available_mb,
        "metrics": {
            "training_jobs_total": metrics_data["total_training_jobs"],
            "training_jobs_completed": metrics_data["completed_jobs"],
            "training_jobs_failed": metrics_data["failed_jobs"]
        }
    }
```

**Health Checks Performed**:
- Database connectivity
- Disk space availability
- Service uptime tracking
- Training job metrics

**Response Statuses**:
- `"healthy"`: All systems operational
- `"degraded"`: Some non-critical issues detected
- `"unhealthy"`: Critical system failures

#### 2. Prometheus Metrics Endpoint (`/metrics`)

**Location**: `python_services/agent_lightning/app.py`

Exposes metrics in Prometheus-compatible format for monitoring dashboards:

```python
@app.get("/metrics")
async def prometheus_metrics():
    """Phase 5: Prometheus-style metrics"""
    success_rate = 0
    if metrics_data["total_training_jobs"] > 0:
        success_rate = (metrics_data["completed_jobs"] / metrics_data["total_training_jobs"]) * 100

    return {
        "training_jobs_total": metrics_data["total_training_jobs"],
        "training_jobs_completed": metrics_data["completed_jobs"],
        "training_jobs_failed": metrics_data["failed_jobs"],
        "training_success_rate_percent": success_rate,
        "api_errors_total": metrics_data["total_api_errors"],
        "timestamp": datetime.now().isoformat()
    }
```

**Monitored Metrics**:
- Total training jobs started
- Successfully completed jobs
- Failed jobs
- Success rate (%)
- Total API errors

**Integration with Monitoring**:
- Prometheus scrapes `/metrics` endpoint at configured interval
- Dashboards alert on success rate drops
- Alert thresholds configurable per environment

#### 3. Retry Logic with Exponential Backoff

**Location**: `python_services/agent_lightning/app.py` → `run_training_job()`

Implements automatic retry logic to handle transient failures:

```python
async def run_training_job(...):
    """Run training with automatic retry on failure"""
    max_retries = 3
    retry_count = 0

    while retry_count < max_retries:
        try:
            # Training execution
            results = train_model(traces, config)

            # Update metrics on success
            metrics_data["completed_jobs"] += 1
            training_jobs[job_id]["status"] = "completed"
            training_jobs[job_id]["results"] = results

            Rails.logger.info(f"✅ Training job {job_id} completed")
            return

        except TransientError as e:
            retry_count += 1

            if retry_count >= max_retries:
                # Max retries exceeded
                metrics_data["failed_jobs"] += 1
                training_jobs[job_id]["status"] = "failed"
                training_jobs[job_id]["error"] = str(e)
                Rails.logger.error(f"❌ Training job {job_id} failed after {max_retries} retries")
                return

            # Exponential backoff: 2s, 4s, 8s
            backoff_seconds = 2 ** retry_count
            Rails.logger.warn(f"⚠️  Retrying job {job_id} in {backoff_seconds}s (attempt {retry_count})")
            await asyncio.sleep(backoff_seconds)
```

**Retry Strategy**:
- **Max Retries**: 3
- **Backoff Formula**: 2^n seconds (2s, 4s, 8s)
- **Total Max Duration**: 14 seconds (2 + 4 + 8)
- **Trigger Conditions**: Network timeouts, transient database errors, service unavailability

#### 4. Global Metrics Tracking

**Location**: `python_services/agent_lightning/app.py`

Tracks system-wide metrics for operational visibility:

```python
metrics_data: Dict[str, Any] = {
    "total_training_jobs": 0,      # Total jobs started
    "completed_jobs": 0,            # Successfully completed
    "failed_jobs": 0,               # Failed after retries
    "total_api_errors": 0          # API communication errors
}

startup_time: float = time.time()  # Track uptime
```

**Metrics Updates**:
- `/api/training/start` increments `total_training_jobs`
- Successful completion increments `completed_jobs`
- Failed completion increments `failed_jobs`
- HTTP errors from Rails increment `total_api_errors`

**Monitoring Dashboard Integration**:
```
Success Rate = (completed_jobs / total_training_jobs) * 100
Error Rate = (total_api_errors / total_training_jobs) * 100
Avg Jobs per Hour = total_training_jobs / (uptime_seconds / 3600)
```

### Deployment Checklist

- [ ] Configure environment variables:
  - `LOG_LEVEL=INFO` (production)
  - `DEBUG=false`
  - `AGENT_LIGHTNING_RUNNERS=4` (or higher for production)

- [ ] Set up monitoring:
  - Prometheus scrape configuration
  - Alert rules for failures
  - Dashboard for key metrics

- [ ] Test retry logic:
  - Simulate transient failures
  - Verify exponential backoff
  - Confirm metrics tracking

- [ ] Load testing:
  - Minimum 10 concurrent training jobs
  - Verify no memory leaks
  - Monitor disk space usage

- [ ] Production logging:
  - Enable debug logs temporarily for monitoring
  - Set up log aggregation
  - Configure log retention

### Production Configuration

**Environment Variables**:
```bash
# Python Service
AGENT_LIGHTNING_ENABLED=true
AGENT_LIGHTNING_SERVICE_URL=http://lightning-service:4747
LOG_LEVEL=INFO
DEBUG=false
AGENT_LIGHTNING_RUNNERS=8  # For production

# Monitoring
PROMETHEUS_SCRAPE_INTERVAL=15s
ALERT_ON_ERROR_RATE_ABOVE=5%  # Alert if >5% errors
ALERT_ON_SUCCESS_RATE_BELOW=90%
```

---

## Phase 6: Prompt Optimization Application

### Objective

Close the reinforcement learning loop by retrieving optimized prompts from completed training jobs and applying them to workflow templates.

### Components Implemented

#### 1. Python Service Endpoint (`/api/training/{job_id}/optimized-prompts`)

**Location**: `python_services/agent_lightning/app.py`

Retrieves optimized prompts from a completed training job:

```python
@app.get("/api/training/{job_id}/optimized-prompts")
async def get_optimized_prompts(job_id: str):
    """Phase 6: Get optimized prompts from training job"""
    job = training_jobs.get(job_id)

    if not job or job["status"] != "completed":
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found or not completed")

    results = job.get("results", {})

    return {
        "job_id": job_id,
        "optimized_prompts": results.get('optimized_prompts', {}),
        "improvement_percentage": results.get('overall_improvement', 0),
        "training_metrics": results.get('training_metrics', {}),
        "timestamp": datetime.now().isoformat()
    }
```

**Response Format**:
```json
{
  "job_id": "job-123",
  "optimized_prompts": {
    "gather_context": {
      "optimized": "Ask the user to provide...",
      "improvement": 15.5
    },
    "execute_goal": {
      "optimized": "To execute this goal, please...",
      "improvement": 12.3
    },
    "validate_result": {
      "optimized": "Validate that the result...",
      "improvement": 8.7
    }
  },
  "improvement_percentage": 12.17,
  "training_metrics": {
    "success_rate": 0.95,
    "avg_tokens_before": 1250,
    "avg_tokens_after": 1100,
    "token_reduction_percent": 12
  }
}
```

#### 2. Rails Client Method (`PythonAgentLightningClient#get_optimized_prompts`)

**Location**: `app/services/python_agent_lightning_client.rb`

Bridges Rails to the Python service:

```ruby
def get_optimized_prompts(job_id)
  raise ServiceUnavailableError unless available?

  response = HTTParty.get(
    "#{BASE_URL}/api/training/#{job_id}/optimized-prompts",
    timeout: 10
  )

  handle_response(response)
rescue HTTParty::Error, Timeout::Error => e
  Rails.logger.error("Failed to get optimized prompts: #{e.message}")
  raise ServiceUnavailableError, "Python service unavailable: #{e.message}"
end
```

#### 3. Prompt Optimizer Service (`AgentLightningPromptOptimizer`)

**Location**: `app/services/agent_lightning_prompt_optimizer.rb`

Orchestrates retrieval and application of optimized prompts:

```ruby
class AgentLightningPromptOptimizer
  def initialize(entity)
    @entity = entity
  end

  def apply_optimizations(job_id)
    # 1. Retrieve optimized prompts from Python service
    result = PythonAgentLightningClient.get_optimized_prompts(job_id)

    # 2. Apply to workflow templates
    optimized_prompts = result['optimized_prompts'] || {}
    applied_count = 0

    optimized_prompts.each do |context_type, prompt_data|
      templates_updated = apply_to_workflow_templates(context_type, prompt_data)
      applied_count += templates_updated.count
    end

    # 3. Create optimization record for tracking
    optimization = AgentLightningOptimization.create!(
      entity: @entity,
      improvement_percentage: result['improvement_percentage'],
      prompts_optimized: optimized_prompts.keys,
      after_prompts: optimized_prompts,
      applied_at: Time.current,
      templates_updated: applied_templates,
      status: "applied"
    )

    { success: true, optimization_id: optimization.id, ... }
  end

  def rollback_optimization(optimization_id)
    # Restore previous prompts and mark as rolled back
    optimization = AgentLightningOptimization.find(optimization_id)
    rollback_to_workflow_templates(optimization.context_types_optimized)
    optimization.mark_rolled_back!

    { success: true, rollback_count: ... }
  end
end
```

#### 4. Optimization Tracking Model (`AgentLightningOptimization`)

**Location**: `app/models/agent_lightning_optimization.rb`

Persists optimization history for audit and rollback:

```ruby
class AgentLightningOptimization < ApplicationRecord
  belongs_to :entity
  belongs_to :agent_training_job, optional: true

  # Status: pending, applied, rolled_back, failed
  enum status: { pending: 0, applied: 1, rolled_back: 2, failed: 3 }

  # Key columns:
  # - optimization_id: Unique identifier
  # - improvement_percentage: % improvement from training
  # - before_prompts: Original prompts (for rollback)
  # - after_prompts: Optimized prompts applied
  # - templates_updated: Array of template names updated
  # - applied_at: When optimization was applied
  # - rolled_back_at: When optimization was rolled back (if any)
  # - rollback_count: Number of times rolled back

  def mark_applied!(templates_count = 0)
    update!(status: "applied", applied_at: Time.current, templates_updated: templates_count)
  end

  def mark_rolled_back!
    update!(status: "rolled_back", rolled_back_at: Time.current, rollback_count: rollback_count + 1)
  end
end
```

**Database Schema**:
```sql
CREATE TABLE agent_lightning_optimizations (
  id BIGINT PRIMARY KEY,
  entity_id BIGINT NOT NULL REFERENCES entities(id),
  agent_training_job_id BIGINT REFERENCES agent_training_jobs(id),
  optimization_id UUID NOT NULL UNIQUE,
  status VARCHAR DEFAULT 'pending',
  improvement_percentage DECIMAL(5,2),
  templates_updated INTEGER,
  templates_modified JSONB,
  context_types_optimized JSONB,
  before_prompts JSONB,
  after_prompts JSONB,
  applied_at TIMESTAMP,
  rolled_back_at TIMESTAMP,
  rollback_count INTEGER DEFAULT 0,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

### Workflow Template Structure

**Before Optimization**:
```yaml
# app/workflow_templates/email_campaign_v2.yml
template_version: 2

phases:
  gather_context:
    instructions: "Please gather information about the email campaign..."
  execute_goal:
    instructions: "Execute the email campaign workflow..."
  validate_result:
    instructions: "Validate that the campaign was created successfully..."
```

**After Optimization**:
```yaml
# Updated by Phase 6
template_version: 2
optimized_at: "2024-11-14T12:30:00Z"
improvement_score: 12.5

phases:
  gather_context:
    instructions: "[OPTIMIZED] Ask the user for..."  # Updated with optimized prompt
  execute_goal:
    instructions: "[OPTIMIZED] To execute the campaign..."  # Updated
  validate_result:
    instructions: "Validate that the campaign was created successfully..."
```

### Application Flow

1. **Training Completes**
   ```
   Python Service completes training job
   → Stores results with optimized_prompts
   ```

2. **Optimization Applied**
   ```
   Rails calls AgentLightningPromptOptimizer.apply_optimizations(job_id)
   → Retrieves optimized prompts via Python service
   → Updates workflow templates with new prompts
   → Creates AgentLightningOptimization record
   ```

3. **Templates Updated**
   ```
   Workflow templates in app/workflow_templates/ updated with new prompts
   → Next workflow execution uses optimized prompts
   → System tracks optimization history
   ```

4. **Monitoring & Rollback**
   ```
   If success rate drops after optimization:
   → Call AgentLightningPromptOptimizer.rollback_optimization(opt_id)
   → Restores previous prompts
   → Marks optimization as rolled back
   ```

### Usage Examples

#### Apply Optimizations from Completed Training

```ruby
entity = Entity.find(123)
optimizer = AgentLightningPromptOptimizer.new(entity)

# After a training job completes
result = optimizer.apply_optimizations("training-job-456")

if result[:success]
  puts "Applied #{result[:applied_count]} optimizations"
  puts "Improvement: #{result[:improvement_percentage]}%"
  puts "Optimization ID: #{result[:optimization_id]}"
else
  puts "Error: #{result[:error]}"
end
```

#### Rollback a Failed Optimization

```ruby
optimizer = AgentLightningPromptOptimizer.new(entity)

# If you notice performance degradation after applying optimizations
result = optimizer.rollback_optimization(optimization_id)

if result[:success]
  puts "Successfully rolled back optimization"
else
  puts "Error: #{result[:error]}"
end
```

#### Check Optimization History

```ruby
# Get all applied optimizations for entity
optimizations = entity.agent_lightning_optimizations.applied.recent

optimizations.each do |opt|
  puts "Optimization: #{opt.optimization_id}"
  puts "  Status: #{opt.status}"
  puts "  Improvement: #{opt.improvement_percentage}%"
  puts "  Templates: #{opt.templates_modified.join(', ')}"
  puts "  Applied: #{opt.applied_at.to_fs(:human)}"
  puts "---"
end
```

### Monitoring & Alerting

#### Key Metrics to Monitor

1. **Optimization Success Rate**
   ```
   % of applied optimizations that improve performance
   Alert: If < 80% of optimizations show improvement
   ```

2. **Average Improvement per Optimization**
   ```
   Average improvement_percentage across all applied optimizations
   Alert: If < 5%
   ```

3. **Rollback Frequency**
   ```
   Number of rollbacks per month
   Alert: If > 10% of applied optimizations rolled back
   ```

4. **Template Update Coverage**
   ```
   % of workflow templates updated by latest optimization
   Alert: If < 90%
   ```

#### Prometheus Alerts

```yaml
# prometheus-rules.yml
groups:
  - name: agent_lightning
    rules:
      - alert: LowOptimizationSuccess
        expr: (optimizer_improved / optimizer_total) < 0.8
        for: 24h
        annotations:
          summary: "Low optimization success rate"

      - alert: HighRollbackRate
        expr: (optimizer_rollbacks / optimizer_applied) > 0.1
        for: 1h
        annotations:
          summary: "High rollback rate detected"
```

### Troubleshooting

#### Optimizations Not Applied

**Symptoms**: Optimization records created but templates not updated

**Solutions**:
1. Check template file permissions: `ls -la app/workflow_templates/`
2. Verify YAML parsing: `YAML.load_file('app/workflow_templates/example_v2.yml')`
3. Check logs for file write errors
4. Ensure sufficient disk space

#### High Rollback Rate

**Symptoms**: Many optimizations being rolled back shortly after application

**Solutions**:
1. Check improvement metrics from training job
2. Review training data quality (may be low-signal data)
3. Consider reducing learning rate or batch size
4. Check for data distribution shift

#### Service Communication Failures

**Symptoms**: "Python service unavailable" errors

**Solutions**:
1. Verify Python service is running: `curl http://localhost:4747/health`
2. Check network connectivity between Rails and Python services
3. Review logs for connection timeouts
4. Increase timeout if network is slow

---

## Complete Phase 5-6 Checklist

### Pre-Deployment

- [ ] All tests passing: `rails test`
- [ ] Phase 5 health checks tested
- [ ] Phase 6 optimization workflow tested end-to-end
- [ ] Database migration created and tested: `rails db:migrate:status`
- [ ] No breaking changes to existing APIs

### Deployment

- [ ] Create database backup
- [ ] Run migrations in production: `rails db:migrate`
- [ ] Deploy Python service with Phase 5 changes
- [ ] Deploy Rails service with Phase 6 changes
- [ ] Verify health endpoint responds: `/health`
- [ ] Verify metrics endpoint works: `/metrics`

### Post-Deployment

- [ ] Monitor for errors: `tail -f log/production.log`
- [ ] Check health dashboards
- [ ] Verify first optimization job completes
- [ ] Test rollback mechanism
- [ ] Confirm templates updated after optimization

### Configuration for Production

```ruby
# config/initializers/agent_lightning.rb

AgentLightning.configure do |config|
  config.enabled = ENV['AGENT_LIGHTNING_ENABLED'] == 'true'
  config.service_url = ENV['AGENT_LIGHTNING_SERVICE_URL']

  # Phase 5: Production settings
  config.retry_max_attempts = 3
  config.retry_backoff_base = 2  # Exponential backoff
  config.metrics_tracking_enabled = true

  # Phase 6: Optimization settings
  config.auto_apply_optimizations = true  # Automatically apply when available
  config.optimization_rollback_threshold = 0.90  # Rollback if success drops below 90%
  config.template_backup_enabled = true  # Backup before applying
end
```

---

## Next Steps

After implementing Phases 5 and 6:

1. **Monitor Production**
   - Watch metrics dashboards
   - Set up alerts for anomalies
   - Review optimization success rates

2. **Iterate on Training**
   - Analyze which optimizations work best
   - Refine training parameters
   - Implement A/B testing for optimizations

3. **Advanced Features** (Future)
   - Multi-prompt optimization strategies
   - Context-aware prompt selection
   - Federated learning across multiple entities
   - Cost optimization balancing tokens vs quality

4. **Documentation**
   - Create operator runbooks
   - Document troubleshooting procedures
   - Build training for support team

---

## References

- Phase 1: Foundation (trace collection)
- Phase 2: Store Adapter (historical data loading)
- Phase 3: Real-time Span Emission (during execution)
- Phase 4: VERL Training (RL model training)
- **Phase 5: Production Deployment** (this doc)
- **Phase 6: Prompt Optimization** (this doc)
