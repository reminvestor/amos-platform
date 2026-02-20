# AI Pipeline Testing Checklist

Progressive testing guide - start with what you can test NOW, then add credentials as they become available.

---

## ✅ Phase 1: Infrastructure Testing (NO CREDENTIALS NEEDED)

**Status**: COMPLETE ✅

All basic infrastructure has been tested and verified working:

- ✅ Database migrations successful
- ✅ Model relationships working
- ✅ State machine validated
- ✅ Event tracking functional
- ✅ Artifact storage working
- ✅ Admin UI accessible
- ✅ Namespaces correct (`AiAgents::Pipeline::*`)

**Evidence**: Test script ran successfully at `/test_pipeline_infrastructure.rb`

**View Test Results**:
```bash
docker compose exec web rails runner test_pipeline_infrastructure.rb
```

**Admin UI**: http://localhost:3000/admin/pipeline/executions

---

## ⏳ Phase 2: AWS Bedrock Testing (HIGHEST PRIORITY)

**What It Unlocks**: All 4 AI agents can run

### **Required Credentials**:
```bash
export AWS_ACCESS_KEY_ID=AKIA...
export AWS_SECRET_ACCESS_KEY=...
export AWS_REGION=us-east-1
```

### **What to Test**:

#### **Test 1: ClarifierAgent** (Claude 3.5 Haiku)
```ruby
# In Rails console
entity = Entity.first
connection = McpConnection.first

pipeline = PipelineExecution.create!(
  entity: entity,
  mcp_connection: connection,
  ticket_id: 'TEST-001',
  ticket_title: 'Add user profile page',
  ticket_description: 'Users should be able to view and edit their profile',
  priority: :high
)

agent_execution = pipeline.agent_executions.create!(
  agent_id: 'clarifier',
  status: :pending,
  inputs: {
    ticket_title: pipeline.ticket_title,
    ticket_description: pipeline.ticket_description
  }
)

agent = AiAgents::Pipeline::ClarifierAgent.new(agent_execution)
agent.execute!

# Expected results:
# - agent_execution.status => "completed"
# - agent_execution.outputs => { needs_clarification: true/false, questions: [...] }
# - Artifacts created: clarification_analysis.json, clarifications.md
# - Tokens used: ~2000
# - Cost: ~$0.02
```

#### **Test 2: PlannerAgent** (Claude Sonnet 4.5)
```ruby
# After ClarifierAgent completes
agent_execution = pipeline.agent_executions.create!(
  agent_id: 'planner',
  status: :pending,
  inputs: {
    ticket_title: pipeline.ticket_title,
    ticket_description: pipeline.ticket_description,
    clarifications: "Inline editing, fields: name/email/avatar/bio"
  }
)

agent = AiAgents::Pipeline::PlannerAgent.new(agent_execution)
agent.execute!

# Expected results:
# - Artifacts created: plan.md, test_spec.yaml
# - Plan contains: files to create, files to modify, test cases
# - Tokens used: ~5000
# - Cost: ~$0.15
```

#### **Test 3: CoderAgent** (Claude Sonnet 4.5) ⚠️ REQUIRES GITHUB
```ruby
# Skip for now unless GitHub is configured
# Will test in Phase 3
```

#### **Test 4: ReviewerAgent** (Claude 3.5 Sonnet) ⚠️ REQUIRES GITHUB
```ruby
# Skip for now unless GitHub is configured
# Will test in Phase 3
```

### **Success Criteria**:
- ✅ ClarifierAgent analyzes ticket, generates questions
- ✅ PlannerAgent creates implementation plan with file list
- ✅ Artifacts are created and stored
- ✅ Tokens and costs are tracked
- ✅ No errors in logs

### **Expected Cost**: ~$0.17 for both tests

---

## ⏳ Phase 3: GitHub Integration (MEDIUM PRIORITY)

**What It Unlocks**: CoderAgent and ReviewerAgent can run

### **Required Setup**:
1. GitHub MCP connection in admin UI
2. GitHub Personal Access Token with repo permissions

### **Test CoderAgent 11-Step Workflow**:
```ruby
# Assuming PlannerAgent has created plan.md artifact
pipeline.update(status: :implementing)

agent_execution = pipeline.agent_executions.create!(
  agent_id: 'coder',
  status: :pending,
  inputs: {
    repository: 'yourorg/yourrepo',
    base_branch: 'main'
  }
)

agent = AiAgents::Pipeline::CoderAgent.new(agent_execution)
agent.execute!

# Expected results:
# - Feature branch created: pipeline/TEST-001-{timestamp}
# - Code files generated (controllers, views, tests)
# - Files pushed to GitHub
# - Pull Request created with formatted body
# - PR URL stored in pipeline.pr_url
# - Workspace cleaned up
# - Cost: ~$0.75
```

### **Test ReviewerAgent**:
```ruby
# After CoderAgent creates PR
pipeline.update(status: :review, pr_url: 'https://github.com/org/repo/pull/123')

agent_execution = pipeline.agent_executions.create!(
  agent_id: 'reviewer',
  status: :pending,
  inputs: {
    pr_url: pipeline.pr_url,
    repository: 'yourorg/yourrepo'
  }
)

agent = AiAgents::Pipeline::ReviewerAgent.new(agent_execution)
agent.execute!

# Expected results:
# - PR diff fetched from GitHub
# - Security scan completed
# - Review comment posted to PR
# - Artifacts: review_report.md, gate.json
# - Decision: approved or needs_changes
# - Cost: ~$0.24
```

### **Success Criteria**:
- ✅ Complete ticket-to-PR flow works
- ✅ All 4 agents execute successfully
- ✅ PR created with proper formatting
- ✅ Code review posted to GitHub
- ✅ Total cost: ~$1.16

---

## ⏳ Phase 4: JIRA Integration (MEDIUM PRIORITY)

**What It Unlocks**: Automatic ticket detection

### **Required Setup**:
1. JIRA connection in admin UI (`/admin/pipeline/connections/new`)
2. JIRA API token + credentials

**Configuration**:
```ruby
# In admin UI
Name: JIRA - Production
System Type: jira
Config:
  url: https://yourcompany.atlassian.net
  email: your-email@company.com
  api_token: your_jira_api_token
  project_key: PROJ

# Test connection button should succeed
```

### **Test Connection**:
```ruby
connection = McpConnection.find_by(system_type: 'jira')
client = AiAgents::Mcp::JiraClient.new(connection)

result = client.test_connection
# => { success: true, message: "Connected as Your Name", data: {...} }
```

### **Test Ticket Fetching**:
```ruby
tickets = client.fetch_recent_tickets(since: 1.hour.ago)
# Should return array of normalized tickets

tickets.first
# => {
#   id: "PROJ-123",
#   title: "...",
#   description: "...",
#   url: "...",
#   status: "Ready for Dev",
#   ...
# }
```

### **Test TicketWatcherJob**:
```ruby
# Make sure you have a ticket in JIRA with status "Ready for Dev"
TicketWatcherJob.perform_now

# Check if pipeline was created
PipelineExecution.where(ticket_system: 'jira').last
# Should show newly created pipeline

# View in admin UI
# http://localhost:3000/admin/pipeline/executions
```

### **Success Criteria**:
- ✅ JIRA connection tests successfully
- ✅ Tickets are fetched and normalized
- ✅ TicketWatcherJob creates pipeline executions
- ✅ Filtering rules work (status, labels, etc.)

---

## ⏳ Phase 5: Slack Notifications (LOW PRIORITY - NICE TO HAVE)

**What It Unlocks**: Real-time notifications during pipeline execution

### **Required Setup**:
```bash
export SLACK_API_TOKEN=xoxb-...
export SLACK_CLARIFICATIONS_CHANNEL=#ai-clarifications
export SLACK_STATUS_CHANNEL=#ai-pipeline-status
export SLACK_ALERTS_CHANNEL=#ai-pipeline-alerts
export SLACK_APPROVALS_CHANNEL=#ai-pipeline-approvals
```

### **Test Notification**:
```ruby
pipeline = PipelineExecution.first
notifier = AiAgents::Notifiers::SlackNotifier.new

# Test state change notification
notifier.send_state_change_notification(pipeline, 'implementing')

# Check Slack channel for message
# Should see threaded message with pipeline details
```

### **Test Threaded Conversations**:
```ruby
# Send multiple notifications
notifier.send_state_change_notification(pipeline, 'review')
notifier.send_state_change_notification(pipeline, 'testing')

# All messages should be in same thread
# pipeline.slack_thread_ts should be set
```

### **Success Criteria**:
- ✅ Messages appear in correct Slack channels
- ✅ Messages are threaded per pipeline
- ✅ Rich formatting with Block Kit
- ✅ Action buttons work (View in Admin UI, View Ticket)

---

## ⏳ Phase 6: Email Notifications (LOW PRIORITY - NICE TO HAVE)

**What It Unlocks**: Email alerts for clarifications and approvals

### **Required Setup**:
```bash
export MAILGUN_API_KEY=key-...
export MAILGUN_DOMAIN=mg.yourdomain.com
export PIPELINE_FROM_EMAIL=ai-pipeline@yourdomain.com
export PIPELINE_FROM_NAME="AI Development Pipeline"
export PIPELINE_DEFAULT_EMAIL=team@yourdomain.com
export PIPELINE_APPROVERS_EMAIL=manager@yourdomain.com
```

### **Test Email**:
```ruby
pipeline = PipelineExecution.first
notifier = AiAgents::Notifiers::EmailNotifier.new

notifier.send_state_change_notification(pipeline, 'review')

# Check email inbox for HTML email
# Should have proper formatting, links, buttons
```

### **Success Criteria**:
- ✅ HTML emails sent successfully
- ✅ Plain text fallback included
- ✅ Links work (admin UI, ticket)
- ✅ Templates render correctly

---

## ⏳ Phase 7: End-to-End Integration Test (FINAL)

**Prerequisites**: All above phases complete

### **Full Workflow Test**:

1. **Create ticket in JIRA** with status "Ready for Dev"
2. **Wait 5 minutes** (TicketWatcherJob runs every 5 min)
3. **Monitor admin UI**: http://localhost:3000/admin/pipeline/executions
4. **Watch logs**: `docker compose logs -f web`
5. **Check Slack**: Messages in #ai-pipeline-status

**Expected Flow**:
```
00:00 - TicketWatcherJob detects ticket
00:01 - Pipeline created (status: NEW)
00:02 - ClarifierAgent analyzes ticket
00:03 - Creates PipelineInteraction if needs clarification
      - Slack message in #ai-clarifications
      - JIRA comment posted
      - Email sent to assignee

[Human answers in admin UI or Slack]

00:15 - PlannerAgent creates implementation plan
00:20 - CoderAgent generates code, creates PR
00:25 - ReviewerAgent reviews code, posts to GitHub
00:30 - Tests run on CI/CD
00:35 - Deploy to Dev environment
00:40 - Deploy to Staging
00:45 - Awaits production approval
      - Slack message in #ai-pipeline-approvals
      - Email to release managers

[Human clicks "Approve" button]

00:47 - Deploy to Production (canary rollout)
01:00 - Status: DONE
```

### **Success Criteria**:
- ✅ Complete flow from ticket → production
- ✅ All agents execute successfully
- ✅ Notifications sent at each step
- ✅ PR created and reviewed
- ✅ Human interactions work (clarifications, approvals)
- ✅ Total time: < 60 minutes
- ✅ Total cost: ~$1.16

---

## 🎯 Testing Priority

### **Test Now** (Can do without external credentials):
1. ✅ Database schema
2. ✅ Model relationships
3. ✅ State machine
4. ✅ Admin UI navigation
5. ✅ Namespace correctness

### **Test Next** (Highest value):
1. ⏳ **AWS Bedrock** - Unlocks all AI agents (~30 min setup)
2. ⏳ **GitHub** - Unlocks code generation and PR creation (~15 min setup)
3. ⏳ **JIRA** - Unlocks automatic ticket detection (~15 min setup)

### **Test Later** (Nice to have):
4. ⏳ Slack notifications (~10 min setup)
5. ⏳ Email notifications (~10 min setup)
6. ⏳ Azure DevOps (if using instead of JIRA)

### **Test Last** (After everything works):
7. ⏳ Full end-to-end integration
8. ⏳ Load testing (multiple pipelines concurrently)
9. ⏳ Failure scenarios (rollback, errors, timeouts)

---

## 📊 Expected Costs for Testing

| Test Phase | AI Calls | Cost |
|-----------|----------|------|
| ClarifierAgent test | 1 | $0.02 |
| PlannerAgent test | 1 | $0.15 |
| CoderAgent test | 1 | $0.75 |
| ReviewerAgent test | 1 | $0.24 |
| **Full pipeline test** | **4** | **$1.16** |
| **10 full tests** | **40** | **$11.60** |

Budget ~$20 for thorough testing.

---

## 🚨 Troubleshooting

### **Test Fails: "uninitialized constant AiAgents::Pipeline"**
```bash
# Restart Rails to reload namespaces
docker compose restart web
```

### **Test Fails: "AWS credentials not configured"**
```bash
# Set environment variables in compose.yaml
# Or export in shell before running docker compose up
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret
docker compose up -d
```

### **Test Fails: "JIRA connection failed"**
- Check API token is valid
- Check email matches JIRA account
- Check URL is correct (https://yourcompany.atlassian.net)
- Test in browser: https://yourcompany.atlassian.net/rest/api/3/myself

### **No tickets detected by TicketWatcherJob**
- Check ticket status matches filter (default: "Ready for Dev")
- Check ticket type is allowed (default: Story, Task, Feature)
- Check ticket has no blocking labels
- Check connection is `active` status
- View connection metadata for custom filters

---

## ✅ Testing Complete Checklist

When you can check all these boxes, the system is fully tested:

- [ ] Phase 1: Infrastructure (database, models, state machine) ✅
- [ ] Phase 2: AWS Bedrock (ClarifierAgent, PlannerAgent)
- [ ] Phase 3: GitHub (CoderAgent, ReviewerAgent, PR creation)
- [ ] Phase 4: JIRA (connection, ticket fetching, TicketWatcherJob)
- [ ] Phase 5: Slack (notifications, threading, channels)
- [ ] Phase 6: Email (HTML templates, recipient routing)
- [ ] Phase 7: End-to-end (full workflow from ticket → production)

---

**Next Steps**: Start with Phase 2 (AWS Bedrock) as it unlocks the most value.

**Estimated Time**: 2-4 hours total for complete testing
**Estimated Cost**: ~$20 in AI tokens

**Questions?** Check [AI_PIPELINE_TESTING_STATUS.md](AI_PIPELINE_TESTING_STATUS.md) for detailed examples.
