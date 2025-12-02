# Parallel Processing System - Testing Guide

## Overview
The parallel processing system is now fully implemented and ready for testing. This guide shows how to test the various features.

## Setup Steps

1. **Run the migration:**
   ```bash
   rails db:migrate
   ```

2. **Restart the Rails server:**
   ```bash
   # Stop existing server (Ctrl+C)
   foreman start -f Procfile.dev
   ```

## Testing Scenarios

### 1. Voice Mode - Immediate Response Test

**Steps:**
1. Open Scout chat
2. Enable voice mode (click the speaker icon)
3. Say: "Hey Amos, analyze my last three campaigns and create a summary report"

**Expected Behavior:**
- **Immediate (< 500ms):** "I'll analyze your campaigns and create that summary report for you."
- **Background:** Three parallel tasks appear in the task panel:
  - Task 1: Fetch campaign data
  - Task 2: Analyze performance metrics
  - Task 3: Generate summary report
- **Final Response:** Complete analysis delivered via voice

### 2. Complex Multi-Task Request

**In Chat:**
```
"Pull data from my top 5 performing email campaigns, 
compare their open rates with industry benchmarks, 
and schedule a meeting with the marketing team to discuss improvements"
```

**Expected Parallel Execution:**
- Task 1: Query campaign database
- Task 2: Fetch industry benchmarks (runs parallel to Task 1)
- Task 3: Statistical analysis (depends on Tasks 1 & 2)
- Task 4: Calendar availability check (runs parallel to Tasks 1 & 2)
- Task 5: Meeting scheduling (depends on Task 4)

**Task Panel Shows:**
- Real-time progress bars
- Task dependencies
- Completion status

### 3. File Processing with Parallel Analysis

**Steps:**
1. Upload 3 documents
2. Send: "Analyze these documents and extract key insights for each"

**Expected Behavior:**
- Each document processed in parallel
- Progress shown for each file
- Results aggregated and presented in order

### 4. Admin Monitoring Dashboard

**Access:** `/admin/parallel_tasks`

**Features to Test:**
- Filter by time range (1h, 24h, 7d)
- Filter by status (Active, Completed, Failed)
- View task details and dependencies
- Cancel active tasks
- Retry failed tasks

## Verification Checklist

### Database
```ruby
# Rails console
rails c

# Check task creation
TaskSession.parallel_tasks.count

# Check dependencies
TaskDependency.all.pluck(:task_session_id, :depends_on_task_id)

# Check voice tasks
TaskSession.where(task_type: 'voice_immediate').count
```

### Logs
Watch for these key indicators:
```
🚀 Using parallel task orchestrator for complex request
🎤 Voice immediate processing completed in XXXms
📊 Task decomposition: X tasks identified
✅ Task #XXX completed
```

### Performance Metrics
- Voice immediate responses: < 500ms
- Task decomposition: < 1s
- Progress updates: Real-time via SSE

## Configuration

### Adjust Parallelism Thresholds
In `app/controllers/scout_controller.rb`:
```ruby
def should_use_parallel_processing?(message, attached_files = [])
  # Modify these patterns for your use case
end
```

### Model Selection
In `app/services/parallel_task_orchestrator.rb`:
```ruby
TASK_TYPES = {
  voice_immediate: { queue: 'critical', model: 'claude-haiku', max_wait_ms: 500 },
  # Adjust models and queues as needed
}
```

## Troubleshooting

### Tasks Not Executing
1. Check SolidQueue is running: `ps aux | grep solid_queue`
2. Verify queues in `config/queue.yml`
3. Check logs: `tail -f log/development.log`

### Voice Mode Issues
1. Ensure TTS is configured
2. Check voice session creation
3. Verify ActionCable connection

### Admin Dashboard Not Loading
1. Ensure admin routes are loaded: `rails routes | grep parallel_tasks`
2. Check admin authentication
3. Verify Bootstrap styling is loaded

## Integration Points

The system integrates with:
- **SolidQueue** - Job processing
- **ActionCable** - Real-time updates
- **BedrockService** - AI model routing
- **ScoutGenericToolsServiceV2** - Tool execution
- **VoiceChannel** - Voice mode communication

## Next Steps

1. **Monitor Performance:**
   - Track average task duration by type
   - Measure model usage costs
   - Analyze parallelism effectiveness

2. **Optimize Patterns:**
   - Fine-tune decomposition prompts
   - Adjust model selection logic
   - Improve dependency detection

3. **Scale Testing:**
   - Load test with multiple concurrent users
   - Test with large file batches
   - Verify queue performance under load
