# Amos Integration Testing Guide

## Overview

The Scout controller now uses Amos as its orchestration layer. This guide explains how to test the integration.

## What Changed

### Before (Complex Scout Controller)
- 2700+ lines of complex logic
- Direct tool execution in controller
- Mixed concerns (orchestration + execution)
- Hard to extend

### After (Amos Integration)
- Scout delegates to Amos orchestrator
- Clean separation of concerns
- Easy to add new agents
- Consistent response handling

## Testing the Integration

### 1. Start the Application
```bash
foreman start -f Procfile.dev
```

### 2. Navigate to Scout Chat
Visit: `http://localhost:3000/scout`

### 3. Test Simple Queries
These should be handled directly by Amos without creating jobs:
- "Hello"
- "What's my business name?"
- "How many contacts do I have?"
- "Search for marketing tips"

### 4. Test Complex Tasks
These should create background jobs with specialized agents:
- "Create a landing page for my product"
- "Import customers from Stripe"
- "Send an email campaign"

### 5. Monitor Background Jobs
Check the logs for:
```
[Amos] Processing message from user: ...
[Amos] Job xxx created
[LandingPageAgent] Starting job xxx
```

## Expected Behavior

### For Simple Queries:
1. Immediate response from Amos
2. No background jobs created
3. Uses minimal tools only

### For Complex Tasks:
1. Amos acknowledges the request
2. Creates appropriate agent job
3. Streams progress updates
4. Handles user input if needed
5. Returns final result

## Debugging

### Check Amos Processing:
```ruby
# In rails console
orchestrator = Amos::Orchestrator.new(user, entity, session_id)
orchestrator.process_message("create a landing page")
```

### Check Job Status:
```ruby
# Check active jobs
Amos::JobRecord.where(status: ['queued', 'running']).pluck(:job_id, :agent_type, :status)
```

### View Amos Logs:
```bash
tail -f log/development.log | grep -E "\[Amos\]|\[.*Agent\]"
```

## Common Issues

### 1. No Response
- Check that Amos services are loaded
- Verify database migration for `amos_jobs` table
- Check ActionCable connection

### 2. Jobs Not Starting
- Ensure SolidQueue workers are running
- Check for failed jobs in `Amos::JobRecord`
- Verify agent job classes exist

### 3. Streaming Not Working
- Verify SSE headers are set correctly
- Check browser console for connection errors
- Ensure `stream_update` is being called

## Next Steps

1. **Add More Agents**: Create specialized agents for:
   - Email campaigns
   - Data imports
   - Report generation
   - Integration management

2. **Enhance Simple Query Handler**: Add more minimal tools:
   - Business metrics
   - Quick stats
   - Help documentation

3. **Improve Job Monitoring**: Create admin dashboard for:
   - Active job monitoring
   - Performance metrics
   - Error tracking

## Architecture Benefits

The Amos integration provides:
- **Scalability**: Easy to add new capabilities
- **Maintainability**: Clean separation of concerns
- **Reliability**: Better error handling and recovery
- **Performance**: Parallel job execution
- **User Experience**: Consistent interaction model

Remember: **Amos doesn't do the work, it ensures the work gets done well!**

