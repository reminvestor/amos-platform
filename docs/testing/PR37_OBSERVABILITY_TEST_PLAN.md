# PR #37 - Observability Enhancements Test Plan

## Overview
This PR adds template analytics and async event persistence to the admin observability dashboard.

## Changes Summary

### 1. Template Analytics (New Feature)
- **File**: `app/controllers/admin/observability_controller.rb`
- **Method**: `compute_template_stats(time_range)`
- **View**: `app/views/admin/observability/_template_analytics.html.erb`
- Aggregates workflow execution data by template showing:
  - Template name and category
  - Total runs
  - Success rate (percentage)
  - Average duration (formatted as seconds/minutes/hours)
  - Unique entities using the template

### 2. Async Event Persistence (Performance Enhancement)
- **Job**: `app/jobs/persist_observability_events_job.rb`
- **Model**: `app/models/observability_event.rb` - Converted from stub to real ActiveRecord model
- **Service**: `app/services/observability_service.rb` - Updated to use async job
- Changes event persistence from synchronous to asynchronous via SolidQueue
- Reduces request latency by moving database writes off the hot path

## Manual Testing Checklist

### Prerequisites
- [ ] Database migrations are up to date: `docker compose exec web rails db:migrate`
- [ ] Docker services are running: `docker compose up -d`
- [ ] Admin user is available for authentication
- [ ] Test data exists: Some WorkflowExecutions with workflow_template_id values

### Template Analytics Testing

#### Visual Rendering
- [ ] Navigate to `/admin/observability/workflows`
- [ ] Verify "Workflow Template Analytics" section appears on the page
- [ ] Verify the section has a bar-chart-3 icon
- [ ] Verify table headers: Template, Category, Total Runs, Success Rate, Avg Duration, Unique Entities

#### Data Accuracy
- [ ] Verify templates are sorted by most-used (highest total runs first)
- [ ] Verify template names are displayed (not slugs)
- [ ] Verify categories are shown as badges
- [ ] Verify total runs count is correct
- [ ] Verify success rate calculation: (completed / total) * 100
- [ ] Verify success rate badge colors:
  - Green (bg-success) for >= 80%
  - Yellow (bg-warning) for >= 50%
  - Red (bg-danger) for < 50%
- [ ] Verify average duration format:
  - Shows "N/A" for templates with no completed executions
  - Shows seconds (e.g., "15.3s") for < 60 seconds
  - Shows minutes (e.g., "2.5m") for 60s - 3600s
  - Shows hours (e.g., "1.2h") for >= 3600s
- [ ] Verify unique entities count is correct

#### Edge Cases
- [ ] Test with no workflow executions (should show "No workflow execution data available yet.")
- [ ] Test with workflows missing workflow_template_id (should be excluded)
- [ ] Test with workflows that have NULL started_at or completed_at (duration should be N/A)
- [ ] Test with different time ranges (7 days, 30 days if filter exists)

#### Cross-Reference with Existing Data
- [ ] Compare template stats with "Workflows by Template" chart on same page
- [ ] Verify counts match between the two visualizations
- [ ] Verify template names/IDs are consistent

### Async Event Persistence Testing

#### Background Job Execution
- [ ] Generate observability events (trigger workflow, use tools, etc.)
- [ ] Check Rails logs for: `"📊 OBSERVABILITY: Flushing X events to database"`
- [ ] Verify PersistObservabilityEventsJob appears in SolidQueue
- [ ] Check SolidQueue logs: `docker compose logs -f web | grep PersistObservabilityEventsJob`
- [ ] Verify events are persisted to `observability_events` table:
  ```sql
  SELECT COUNT(*) FROM observability_events;
  ```

#### Event Data Integrity
- [ ] Verify event records have correct structure:
  - `event_type` is populated
  - `entity_id` is set (if available in event data)
  - `user_id` is set (if available in event data)
  - `metadata` jsonb contains event data
  - `duration_ms` is set (if available)
  - `status` is "success" or "error"
  - `error_message` is set on errors
  - `created_at` uses event timestamp or Time.current
- [ ] Verify batch_insert handles empty arrays gracefully
- [ ] Verify batch_insert error handling (logs error but doesn't raise)

#### Performance Impact
- [ ] Compare request latency before/after PR (should be lower)
- [ ] Verify buffer flush doesn't block main thread
- [ ] Check memory usage (buffer is cleared after duplication)

### Integration with Observability Dashboard

#### Performance Tab
- [ ] Navigate to `/admin/observability/performance`
- [ ] Verify events are queryable by event_type
- [ ] Verify average durations are calculated correctly
- [ ] Verify performance charts render with new event data

#### Errors Tab
- [ ] Navigate to `/admin/observability/errors`
- [ ] Verify error events are captured
- [ ] Verify error_message field is displayed
- [ ] Verify error grouping by type works

### Database Migration Verification
- [ ] Confirm `observability_events` table exists
- [ ] Verify indexes are created:
  - `index_observability_events_on_event_type`
  - `index_observability_events_on_status`
  - `index_observability_events_on_entity_id_and_created_at`
  - `index_observability_events_on_resource_type_and_resource_id`
  - `index_observability_events_on_created_at`

### Regression Testing
- [ ] Verify existing workflow stats still render correctly
- [ ] Verify "Workflows by Template" chart still works
- [ ] Verify "Workflows by Entity" chart still works
- [ ] Verify average execution time calculation unchanged
- [ ] Verify workflow trend chart still renders
- [ ] Verify time range filtering still works
- [ ] Verify status filtering still works
- [ ] Verify pagination still works (limit 100)

## Test Data Setup

### Creating Test Workflow Executions
```ruby
# In Rails console
entity = Entity.first
user = entity.users.first

# Create completed workflow
WorkflowExecution.create!(
  entity: entity,
  user: user,
  workflow_template_id: "create_landing_page_v2",
  status: "completed",
  started_at: 2.minutes.ago,
  completed_at: 1.minute.ago
)

# Create failed workflow
WorkflowExecution.create!(
  entity: entity,
  user: user,
  workflow_template_id: "create_landing_page_v2",
  status: "failed",
  started_at: 3.minutes.ago,
  completed_at: 2.minutes.ago
)

# Create in-progress workflow
WorkflowExecution.create!(
  entity: entity,
  user: user,
  workflow_template_id: "email_campaign_v2",
  status: "in_progress",
  started_at: 1.minute.ago
)
```

### Triggering Observability Events
```ruby
# In Rails console
service = ObservabilityService.instance

# Manually track events (these will be flushed async)
service.track_event(:workflow_execution, {
  entity_id: entity.id,
  user_id: user.id,
  workflow_execution_id: 123,
  status: "completed",
  duration_ms: 5000
})

# Force flush to trigger background job immediately
service.send(:flush_events_buffer)
```

## Expected Outcomes

### Success Criteria
1. Template analytics table renders with accurate aggregated data
2. Template stats match underlying WorkflowExecution records
3. Success rate badges display with correct colors
4. Duration formatting is human-readable and accurate
5. Background job processes events without errors
6. ObservabilityEvent records are created in database
7. No performance degradation in request/response cycle
8. Existing observability features continue to work
9. Error handling gracefully handles edge cases

### Known Limitations
- Template analytics only shows data for workflows with `workflow_template_id` set
- Duration is only calculated for completed workflows with both `started_at` and `completed_at`
- Async persistence means slight delay between event generation and database visibility
- Template metadata requires either WorkflowTemplate DB record or YAML template file

## Automated Test Coverage
See automated test files:
- `test/controllers/admin/observability_controller_test.rb` (template analytics)
- `test/jobs/persist_observability_events_job_test.rb` (async job)
- `test/models/observability_event_test.rb` (model validations and batch_insert)
- `test/integration/observability_event_persistence_integration_test.rb` (end-to-end)
