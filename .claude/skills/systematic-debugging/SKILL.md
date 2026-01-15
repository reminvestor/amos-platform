# Systematic Debugging

A 4-phase root cause analysis methodology for complex bugs in AI agent systems.

## Description

This skill provides a structured approach to debugging that avoids "shotgun debugging" (random changes hoping something works). It's especially valuable for AI agent code where issues can cascade through workflows, tools, and streaming responses.

**Use this skill when:**
- Facing complex bugs that aren't immediately obvious
- Tests are failing for unclear reasons
- AI responses are wrong or inconsistent
- Workflow execution stalls or produces unexpected results
- Integration with external APIs fails intermittently

## Instructions

### The 4-Phase Debugging Process

```
┌─────────────────────────────────────────────┐
│  Phase 1: REPRODUCE  → Reliable repro steps │
│  Phase 2: ISOLATE    → Narrow the scope     │
│  Phase 3: IDENTIFY   → Find root cause      │
│  Phase 4: VERIFY     → Confirm fix works    │
└─────────────────────────────────────────────┘
```

### Phase 1: REPRODUCE (Don't Skip This!)

**Goal:** Establish reliable reproduction steps.

Without reliable reproduction, you're debugging blind.

**Steps:**
1. Document exact steps to trigger the bug
2. Note the environment (Docker, local, production)
3. Identify data dependencies (specific entities, users)
4. Determine if it's consistent or intermittent
5. Create a minimal test case if possible

**Template:**
```markdown
## Bug Reproduction

**Environment:** Docker development
**Entity:** Demo Company (ID: 123)
**User:** test@example.com

**Steps to reproduce:**
1. Go to Scout chat
2. Type "Create a landing page for summer sale"
3. Wait for tool execution
4. Observe error in streaming response

**Expected:** Landing page created successfully
**Actual:** Error "undefined method `content' for nil:NilClass"

**Consistent?:** Yes, 100% reproducible
```

### Phase 2: ISOLATE (Narrow the Scope)

**Goal:** Identify which component is failing.

**AMOS Component Checklist:**

```
[ ] Controller level (ScoutController, AmosController)
[ ] Agent/Executor level (PlannerAgentService, GoalExecutor)
[ ] Tool level (specific tool from ToolCatalog)
[ ] Service level (BedrockService, IntegrationApiService)
[ ] Model level (validations, callbacks, scopes)
[ ] Database level (migrations, constraints, data)
[ ] External API level (AWS Bedrock, integrations)
[ ] Frontend level (Stimulus controller, SSE handling)
```

**Isolation Techniques:**

**1. Binary Search:**
```ruby
# Add checkpoints to find where things go wrong
Rails.logger.info "CHECKPOINT 1: About to call planner"
result = PlannerAgentService.new(entity).analyze(message)
Rails.logger.info "CHECKPOINT 2: Planner returned: #{result.inspect}"
```

**2. Test in Isolation:**
```ruby
# Rails console - test component directly
tool = Tools::GenerateLandingPageTool.new(
  user: User.first,
  entity: Entity.first
)
result = tool.execute(title: "Test", content: "Test content")
puts result.inspect
```

**3. Check Logs:**
```bash
# Docker logs for web service
docker-compose logs -f web | grep -E "(ERROR|WARN|CHECKPOINT)"

# Rails logs
tail -f log/development.log
```

### Phase 3: IDENTIFY (Root Cause Analysis)

**Goal:** Find the actual root cause, not just symptoms.

**The 5 Whys Technique:**

```
Bug: Landing page generation fails

Why 1: Tool returns nil
Why 2: BedrockService response is empty
Why 3: API call times out
Why 4: Prompt is too large (>200k tokens)
Why 5: File content was included multiple times  ← ROOT CAUSE
```

**Common Root Causes in AMOS:**

| Symptom | Likely Root Cause |
|---------|-------------------|
| "undefined method for nil" | Missing entity scoping, uninitialized variable |
| Workflow stalls | Tool returned error, executor didn't handle |
| Wrong entity data | Missing `current_entity` filter |
| Streaming cuts off | Timeout, uncaught exception |
| Tests pass locally, fail CI | Environment variables, timing, fixtures |
| Intermittent failures | Race condition, external API rate limits |

**Evidence Gathering:**

```ruby
# Add comprehensive logging temporarily
def execute(args)
  Rails.logger.info "[DEBUG] #{self.class.name}#execute"
  Rails.logger.info "[DEBUG] args: #{args.inspect}"
  Rails.logger.info "[DEBUG] user: #{@user&.id}"
  Rails.logger.info "[DEBUG] entity: #{@entity&.id}"

  # ... implementation

rescue => e
  Rails.logger.error "[DEBUG] Exception: #{e.class} - #{e.message}"
  Rails.logger.error "[DEBUG] Backtrace: #{e.backtrace.first(10).join("\n")}"
  raise
end
```

### Phase 4: VERIFY (Confirm the Fix)

**Goal:** Prove the fix works and doesn't break other things.

**Verification Checklist:**

```markdown
## Fix Verification

**Root Cause:** Missing nil check in WorkflowContext lookup

**Fix Applied:**
- File: app/services/agents/goal_executor.rb
- Line: 127
- Change: Added `&.dig(:data)` safe navigation

**Verification Steps:**

1. [x] Original bug no longer reproduces
   - Tested with exact reproduction steps
   - Ran 5 times, all successful

2. [x] Wrote regression test
   - test/services/agents/goal_executor_test.rb:234
   - Test covers nil context scenario

3. [x] Existing tests pass
   - `docker-compose run --rm web rails test` - All green

4. [x] Related functionality works
   - Other workflows still execute correctly
   - Tool catalog unchanged

5. [x] No new warnings/errors in logs
   - Monitored logs during test
   - No unexpected output
```

### Debugging AMOS-Specific Issues

**Workflow Debugging:**
```ruby
# Find stuck workflows
WorkflowExecution.where(status: 'in_progress')
  .where('updated_at < ?', 30.minutes.ago)
  .each { |w| puts "Stuck: #{w.id} - #{w.workflow_template}" }

# Check workflow context
wf = WorkflowExecution.find(123)
puts wf.workflow_contexts.map { |c| [c.phase, c.key, c.value] }
```

**Tool Debugging:**
```ruby
# List all registered tools
Tools::ToolCatalog.instance.all_tools.keys.sort

# Test specific tool
tool = Tools::ToolCatalog.instance.get_tool('generate_ai_landing_page')
puts tool.definition
```

**Streaming Debugging:**
```javascript
// Browser console - monitor SSE events
const eventSource = new EventSource('/scout/chat_stream');
eventSource.onmessage = (e) => console.log('MSG:', JSON.parse(e.data));
eventSource.onerror = (e) => console.error('ERR:', e);
```

### Debug Commands

```bash
# Rails console in Docker
docker-compose exec web rails console

# Interactive debugging with byebug
# Add `byebug` to code, then attach:
docker attach agent_marketing-web-1

# Check recent errors
docker-compose exec web rails runner "puts Rails.logger.level"
```

## Examples

**Debugging a failing workflow:**
```
Use systematic-debugging skill for "landing page workflow fails silently"
```

**Debugging flaky tests:**
```
Use systematic-debugging skill for "campaign_test.rb fails intermittently"
```

**Debugging integration issues:**
```
Use systematic-debugging skill for "Stripe webhook not processed"
```

## Anti-Patterns (Don't Do These)

| Anti-Pattern | Why It's Bad | Do This Instead |
|--------------|--------------|-----------------|
| Shotgun debugging | Random changes, no learning | Follow 4-phase process |
| Debugging in production | Risk to users, limited visibility | Reproduce locally first |
| Removing error handling | Hides bugs, doesn't fix them | Fix root cause |
| "It works on my machine" | Environment-specific issues | Use Docker consistently |
| Assuming external APIs work | APIs fail, rate limit, change | Add logging, verify responses |

## Resources

- [Test-Driven Development](../test-driven-development/SKILL.md) - Write regression tests
- [Running Tests](../running-tests/SKILL.md) - Execute tests during debugging
- [Docker Management](../managing-docker-development/SKILL.md) - Container debugging
