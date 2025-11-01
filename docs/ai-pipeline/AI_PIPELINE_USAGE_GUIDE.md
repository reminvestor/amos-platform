# AI Pipeline - Usage Guide

**Last Updated**: January 29, 2025
**Status**: Production Ready
**Version**: 1.0 with MCP Integration

---

## 🚀 Quick Start

### 1. Configure GitHub Connection

1. Navigate to **Admin Portal** → **AI Pipeline** → **Connections**
2. Click "New Connection"
3. Select **System Type**: GitHub
4. Enter:
   - **Name**: "GitHub - Your Org"
   - **Organization**: Your GitHub org name (e.g., "NuvolaNetworks")
   - **Repository**: Your repo name (e.g., "agent_marketing")
   - **API Token**: Your GitHub Personal Access Token with repo permissions
5. Click "Save"
6. Test the connection - you should see "✅ Active"

### 2. Configure JIRA Connection (Optional - For Automatic Ticket Watching)

1. Click "New Connection"
2. Select **System Type**: JIRA
3. Enter:
   - **Name**: "JIRA - Project Name"
   - **URL**: Your JIRA instance URL
   - **Email**: Your JIRA account email
   - **API Token**: Your JIRA API token
   - **Project Key**: Your JIRA project key
4. Click "Save"

### 3. Manually Trigger a Pipeline (Development/Testing)

```ruby
# In Rails console or via script

# Find your entity and GitHub connection
entity = Entity.find_by(name: 'Demo Company')
github_connection = McpConnection.find_by(entity: entity, system_type: 'github')

# Create a pipeline execution manually
pipeline = PipelineExecution.create!(
  entity: entity,
  git_connection: github_connection,
  ticket_id: 'TEST-123',
  ticket_system: 'manual',
  ticket_url: 'https://yourproject.atlassian.net/browse/TEST-123',
  ticket_title: 'Add user authentication feature',
  ticket_description: <<~DESC
    We need to add user authentication to the application.

    Requirements:
    - Users should be able to sign up with email/password
    - Users should be able to log in
    - Sessions should persist for 30 days
    - Add password reset functionality
  DESC,
  priority: :high,
  ticket_metadata: {}
)

# Start the pipeline
ProcessPipelineJob.perform_later(pipeline.id)

# Check status
pipeline.reload.status  # => "new" → "clarifying" → "planning" → ...
```

### 4. Enable Automatic Ticket Watching (Production)

Add to `config/initializers/solid_queue.rb` or run manually:

```ruby
# Run every 5 minutes to check for new JIRA/Azure DevOps tickets
TicketWatcherJob.set(wait_until: 5.minutes.from_now).perform_later

# Or set up recurring job in SolidQueue config
```

---

## 📊 Monitoring Pipeline Executions

### Admin Dashboard

Navigate to **Admin Portal** → **AI Pipeline** → **Executions**

You'll see:
- **Total Executions**: Count of all pipeline runs
- **Active**: Currently running pipelines
- **Completed**: Successful completions
- **Total Cost**: AI token costs across all runs

### Execution Detail View

Click on any pipeline execution to see:

**Overview**:
- Ticket ID and title
- Current status
- Duration
- Total cost and tokens used
- PR URL (when created)
- Branch name

**Agent Timeline**:
```
10:00 ClarifierAgent  ✅ completed  $0.02  2,000 tokens
10:01 PlannerAgent    ✅ completed  $0.15  5,000 tokens
10:05 CoderAgent      ✅ completed  $0.75 10,000 tokens
10:18 ReviewerAgent   ✅ completed  $0.24  8,000 tokens
```

**Artifacts** (downloadable):
- clarifications.json
- plan.md
- test_spec.yaml
- generated_code.json
- review_report.json

**Events** (full audit trail):
- ticket.intake
- ticket.clarified
- plan.ready
- pr.opened
- pr.approved
- human.approved
- prod.promoted

---

## 🤖 Agent Workflow Explained

### 1. ClarifierAgent (Claude 3.5 Haiku - $0.02)

**What it does**:
- Analyzes ticket description for clarity
- Identifies missing requirements or ambiguity
- Asks clarifying questions if needed

**When it blocks**:
- If `needs_clarification: true`, pipeline status → **BLOCKED**
- Questions sent via Slack/Email to assignee
- Waits for human response (2-hour timeout)

**Output**:
```json
{
  "needs_clarification": false,
  "summary": "Add JWT-based authentication...",
  "requirements": [
    "User registration with email/password",
    "Login endpoint with JWT token generation",
    "Session persistence for 30 days"
  ]
}
```

### 2. PlannerAgent (Claude Sonnet 4.5 - $0.15)

**What it does**:
- Creates detailed implementation plan
- Defines acceptance tests
- Identifies files to create/modify

**Output** (saved as `plan.md`):
```markdown
# Implementation Plan: Add User Authentication

## Files to Create
- app/models/user.rb
- app/controllers/sessions_controller.rb
- db/migrate/XXX_create_users.rb

## Implementation Steps
1. Create User model with bcrypt
2. Add sessions controller
3. Implement JWT token generation
4. Add authentication middleware

## Acceptance Tests
- User can sign up with valid email/password
- User can log in and receive JWT token
- Token expires after 30 days
```

### 3. CoderAgent (Claude Sonnet 4.5 - $0.75)

**11-Step Workflow**:

1. **Creates workspace**: `/tmp/pipeline-{id}/coder/` (0700 permissions)
2. **Clones repository**: Using GitHub credentials
3. **Creates branch**: `pipeline/TEST-123-1738175280`
4. **Reads plan**: From PlannerAgent artifact
5. **Generates code**: Claude produces complete files
6. **Parses files**: Extracts FILE: markers
7. **Identifies tests**: Looks for test/spec files
8-9. **Pushes to GitHub**: Via MCP `push_files` (commit + push combined)
10. **Creates PR**: With formatted body and metadata
11. **Cleanup**: Removes workspace

**Generated PR Body**:
```markdown
## 🎫 Ticket
**TEST-123**: Add user authentication feature

## 📋 Implementation Plan
[First 20 lines of plan.md...]

## 📁 Files Changed (5)
- `app/models/user.rb`
- `app/controllers/sessions_controller.rb`
- `db/migrate/XXX_create_users.rb`
- `spec/models/user_spec.rb`
- `spec/controllers/sessions_controller_spec.rb`

## 🤖 Generated by AI Pipeline
- Agent: CoderAgent
- Model: Claude Sonnet 4.5
- Timestamp: 2025-01-29T10:05:00Z

## ✅ Next Steps
1. ReviewerAgent will analyze code quality
2. Automated tests will run
3. Human approval for production deployment
```

### 4. ReviewerAgent (Claude 3.5 Sonnet - $0.24)

**What it does**:
- Fetches PR diff from GitHub
- Analyzes code quality
- Checks for security vulnerabilities
- Verifies test coverage
- Reviews documentation

**Checks**:
- ✓ No secrets in code
- ✓ No known vulnerabilities
- ✓ Follows code patterns
- ✓ Has sufficient tests
- ✓ Documentation updated

**Output**:
```json
{
  "approved": true,
  "issues": [],
  "suggestions": [
    "Consider adding index on users.email for faster lookups"
  ],
  "summary": "Code quality is excellent. All checks passed."
}
```

---

## 🎛️ State Machine

```
NEW
 ↓
CLARIFYING (ClarifierAgent)
 ↓ (if clear)
PLANNING (PlannerAgent)
 ↓
IMPLEMENTING (CoderAgent)
 ↓
REVIEW (ReviewerAgent)
 ↓ (if approved)
TESTING
 ↓
DEV
 ↓
STAGING
 ↓
AWAITING_PROD_APPROVAL (👤 Human Gate)
 ↓ (if approved)
PROD
 ↓
DONE ✅
```

**Terminal States**:
- **DONE**: Successfully deployed to production
- **FAILED**: Error occurred, can retry
- **ROLLED_BACK**: Production rollback triggered

---

## 👤 Human Interaction Points

### 1. Clarification Request (BLOCKED)

**Trigger**: ClarifierAgent needs more information

**How you'll be notified**:
- Slack message in #ai-clarifications channel
- Email to ticket assignee
- Dashboard shows "BLOCKED" status

**How to respond**:
1. Go to **Admin → Pipeline → Executions**
2. Click on the blocked execution
3. View clarification questions
4. Click "Respond"
5. Enter answers
6. Submit

**What happens next**:
- Pipeline status → CLARIFYING
- ClarifierAgent re-runs with your answers
- If satisfied, continues to PLANNING

### 2. Production Approval (AWAITING_PROD_APPROVAL)

**Trigger**: After staging tests pass

**How you'll be notified**:
- Slack message in #deployments channel
- Email to release managers
- Dashboard shows "Awaiting Approval"

**Information provided**:
- PR URL with full diff
- Test results from dev and staging
- Code review summary
- Files changed

**How to approve**:
1. Review the PR on GitHub
2. Check test results
3. In Admin → Pipeline → Executions → [execution]
4. Click "Approve Production Deployment"

**What happens next**:
- Pipeline status → PROD
- PR merged to main
- Deploy to production
- Health checks monitored
- If successful → DONE
- If failures → ROLLED_BACK

---

## 💰 Cost Tracking

### Per Ticket Average: ~$1.16

```
ClarifierAgent  (Haiku 3.5)      ~2K tokens    $0.02
PlannerAgent    (Sonnet 4.5)     ~5K tokens    $0.15
CoderAgent      (Sonnet 4.5)    ~10K tokens    $0.75
ReviewerAgent   (Sonnet 3.5)     ~8K tokens    $0.24
───────────────────────────────────────────────────
TOTAL                           ~25K tokens    $1.16
```

### Monthly Projection (10 tickets/day)

- Working days: 22
- Monthly tickets: 220
- Monthly AI cost: **$255**
- Infrastructure cost: **$0** (uses existing AMOS)
- **Total: $255/month**

### Cost Controls

View real-time costs:
- **Admin → Pipeline → Executions** shows total cost
- Each execution detail shows breakdown by agent
- Token usage tracked per agent

---

## 🔍 Troubleshooting

### Pipeline Stuck in IMPLEMENTING

**Cause**: CoderAgent may have failed

**Check**:
1. Admin → Executions → [your pipeline]
2. Look at CoderAgent in agent timeline
3. Click to view logs

**Common issues**:
- GitHub token expired → Update connection
- Branch already exists → Delete branch manually
- Code generation timeout → Increase timeout

**Fix**:
```ruby
# In Rails console
pipeline = PipelineExecution.find(123)
pipeline.retry!  # Restarts from beginning
```

### No Tickets Being Detected

**Cause**: TicketWatcherJob not running or connection misconfigured

**Check**:
1. Admin → Connections → Test your JIRA connection
2. Should see "✅ Active" status

**Manually trigger watcher**:
```ruby
TicketWatcherJob.perform_now
```

**Check logs**:
```bash
docker compose logs web --tail=100 | grep TicketWatcher
```

### PR Creation Fails

**Cause**: GitHub permissions or rate limits

**Check**:
1. Verify GitHub token has `repo` scope
2. Check rate limit:
```ruby
github_connection = McpConnection.find_by(system_type: 'github')
client = Git::GithubClient.new(github_connection)
client.test_connection
```

---

## 🔐 Security & Best Practices

### API Token Management

**GitHub Token**:
- Required scopes: `repo`, `write:discussion`
- Create at: https://github.com/settings/tokens
- Store in database (encrypted automatically)
- **Never commit tokens to git**

**JIRA Token**:
- Create API token: https://id.atlassian.com/manage-profile/security/api-tokens
- Required permissions: Read/Write Issues, Add Comments
- Store in database (encrypted)

### Workspace Security

- All workspaces created with `0700` permissions (owner-only)
- Cleaned up automatically after 24 hours
- Never stores sensitive data in artifacts
- Git clone uses HTTPS with token (not SSH)

### Secret Scanning

ReviewerAgent automatically checks for:
- Hardcoded API keys
- AWS credentials
- Database passwords
- Private keys
- `.env` file patterns

---

## 📈 Performance Optimization

### Reduce Costs

**Strategy 1**: Use different models
```ruby
# In agent class, override model method
def model
  'claude-3-5-haiku-20241022'  # Cheaper for simple tasks
end
```

**Strategy 2**: Adjust agent parameters
```ruby
# Reduce max_tokens if responses are too long
def execute_logic
  call_claude(prompt, max_tokens: 2000)  # vs default 4000
end
```

### Increase Speed

**Strategy 1**: Run jobs in parallel
```ruby
# In config/solid_queue.yml
queues:
  pipeline:
    priority: 10
    threads: 5  # Increase from 3
```

**Strategy 2**: Skip unnecessary agents
```ruby
# For simple tickets, skip clarifier
if ticket.description.length > 500
  pipeline.update!(status: :planning)  # Skip to planning
end
```

---

## 🎯 Advanced Usage

### Custom Workflows Per Ticket Type

```ruby
# In TicketWatcherJob
def check_connection_for_tickets(connection)
  tickets.each do |ticket|
    priority = determine_priority(ticket)

    pipeline = PipelineExecution.create!(
      entity: connection.entity,
      ticket_id: ticket[:id],
      # ... other fields
    )

    # Skip clarifier for bug fixes
    if ticket[:labels]&.include?('bug')
      pipeline.update!(status: :planning)
    end

    ProcessPipelineJob.perform_later(pipeline.id)
  end
end
```

### Integration with Existing Workflows

```ruby
# Trigger pipeline from Scout chat
class Tools::TriggerPipelineTool < BaseTool
  def execute(args)
    pipeline = PipelineExecution.create!(
      entity: current_entity,
      ticket_id: args[:ticket_id],
      ticket_title: args[:title],
      ticket_description: args[:description]
    )

    ProcessPipelineJob.perform_later(pipeline.id)

    success_response(
      message: "Pipeline started for #{args[:ticket_id]}",
      data: { pipeline_url: admin_pipeline_execution_url(pipeline) }
    )
  end
end
```

---

## 📚 Related Documentation

- [AI_PIPELINE_SPEC.md](AI_PIPELINE_SPEC.md) - Complete technical specification
- [AI_PIPELINE_HOW_IT_WORKS.md](AI_PIPELINE_HOW_IT_WORKS.md) - Detailed workflow explanation
- [CLAUDE.md](../CLAUDE.md) - Overall AMOS architecture

---

## 🆘 Support & Feedback

**Issues**:
- Check logs: `docker compose logs web --tail=200`
- View pipeline status: Admin → Pipeline → Executions
- Retry failed pipelines: Click "Retry" button

**Questions**:
- Review this guide
- Check the spec documents
- Look at example executions in dashboard

---

**Happy Automating! 🚀**
