# 📊 AI Development Pipeline - How It Works

**Last Updated**: January 29, 2025
**Status**: Production Ready
**Cost**: ~$1.16 per ticket

---

## 🔄 High-Level Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        TICKET SYSTEMS (Input)                            │
│  ┌──────────┐        ┌──────────────┐        ┌──────────────┐          │
│  │   JIRA   │   OR   │ Azure DevOps │   OR   │ Manual Input │          │
│  └─────┬────┘        └──────┬───────┘        └──────┬───────┘          │
└────────┼────────────────────┼───────────────────────┼──────────────────┘
         │                    │                       │
         └────────────────────┼───────────────────────┘
                              ▼
                    ┌──────────────────┐
                    │ TicketWatcherJob │ (Polls every 5 min)
                    │   or Webhook     │
                    └────────┬─────────┘
                             ▼
                ┌────────────────────────┐
                │ PipelineExecution      │ (Status: NEW)
                │ - Ticket ID: JIRA-123  │
                │ - Title, Description   │
                └────────┬───────────────┘
                         ▼
                ┌─────────────────────┐
                │ ProcessPipelineJob  │ (Main Orchestrator)
                └────────┬────────────┘
                         ▼
         ┌───────────────────────────────────────┐
         │   Pipeline::Orchestrator              │
         │   (14-State State Machine)            │
         └───────────────┬───────────────────────┘
                         ▼
         ┌───────────────────────────────────────┐
         │          AGENT EXECUTION              │
         │        (Background Jobs)              │
         └───────────────────────────────────────┘
```

---

## 🤖 Detailed Agent Flow (The Magic!)

### STATE 1: CLARIFYING

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 🤖 ClarifierAgent (Claude 3.5 Haiku - $0.02)                            │
│                                                                          │
│ INPUT:  Ticket description                                              │
│ DOES:   - Analyzes requirements for clarity                             │
│         - Checks for ambiguity or missing information                   │
│         - Generates clarification questions if needed                   │
│                                                                          │
│ OUTPUT: Either:                                                         │
│         ✅ Requirements clear → move to PLANNING                        │
│         ❓ Needs clarification → BLOCKED (ask human via Slack/Email)    │
│                                                                          │
│ ARTIFACTS: clarifications.json                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### STATE 2: PLANNING

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 🤖 PlannerAgent (Claude Sonnet 4.5 - $0.15)                             │
│                                                                          │
│ INPUT:  - Requirements + clarifications                                 │
│         - Ticket description and metadata                               │
│                                                                          │
│ DOES:   - Creates detailed implementation plan                          │
│         - Defines acceptance tests                                      │
│         - Identifies files to create/modify                             │
│         - Specifies technical approach                                  │
│                                                                          │
│ OUTPUT: plan.md, test_spec.yaml, architecture_diagram.mermaid           │
│                                                                          │
│ ARTIFACTS: Saved to pipeline_artifacts table                            │
└─────────────────────────────────────────────────────────────────────────┘
```

### STATE 3: IMPLEMENTING

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 🤖 CoderAgent (Claude Sonnet 4.5 - $0.75)                               │
│                                                                          │
│ WORKSPACE: /tmp/pipeline-{execution_id}/coder/                          │
│                                                                          │
│ STEPS:                                                                  │
│   1. Creates isolated workspace (0700 permissions)                      │
│   2. Clones repository from GitHub/Azure Repos                          │
│   3. Creates feature branch: pipeline/{ticket_id}-{timestamp}           │
│   4. Reads implementation plan                                          │
│   5. Generates code based on plan                                       │
│   6. Writes files to workspace                                          │
│   7. Creates/updates tests                                              │
│   8. Commits changes with descriptive message                           │
│   9. Pushes branch to remote                                            │
│  10. Creates Pull Request via GitHub/Azure API                          │
│  11. Cleanup workspace                                                  │
│                                                                          │
│ OUTPUT: - PR URL                                                        │
│         - PR ID                                                         │
│         - Branch name                                                   │
│         - Code artifact                                                 │
└─────────────────────────────────────────────────────────────────────────┘
```

### STATE 4: REVIEW

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 🤖 ReviewerAgent (Claude 3.5 Sonnet - $0.24)                            │
│                                                                          │
│ INPUT:  - PR URL and ID                                                 │
│         - Repository information                                        │
│                                                                          │
│ DOES:   - Fetches PR diff from GitHub/Azure                             │
│         - Analyzes code quality                                         │
│         - Checks for security vulnerabilities                           │
│         - Verifies test coverage                                        │
│         - Reviews documentation                                         │
│         - Checks for performance issues                                 │
│                                                                          │
│ CHECKS:                                                                 │
│   ✓ No secrets in code                                                 │
│   ✓ No known vulnerabilities                                           │
│   ✓ Follows code patterns                                              │
│   ✓ Has sufficient tests                                               │
│   ✓ Documentation updated                                              │
│                                                                          │
│ OUTPUT: Either:                                                         │
│         ✅ Approved → move to TESTING                                   │
│         ❌ Changes needed → back to IMPLEMENTING                        │
│                                                                          │
│ ARTIFACTS: review_report.json, security_scan.json                       │
└─────────────────────────────────────────────────────────────────────────┘
```

### STATE 5-7: TESTING → DEV → STAGING

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 🤖 CuaPackAgent (Future - Synthetic Testing)                            │
│                                                                          │
│ TESTING:  - Run unit tests                                              │
│           - Run integration tests                                       │
│           - Check test coverage                                         │
│                                                                          │
│ DEV:      - Deploy to dev environment                                   │
│           - Run synthetic user tests                                    │
│           - Performance testing                                         │
│                                                                          │
│ STAGING:  - Deploy to staging environment                               │
│           - Full regression test suite                                  │
│           - Load testing                                                │
│           - Accessibility testing                                       │
│                                                                          │
│ TOOLS:    Playwright, Lighthouse, API tester                            │
│                                                                          │
│ ARTIFACTS: test_report.json, screenshots/, performance_metrics.json     │
└─────────────────────────────────────────────────────────────────────────┘
```

### STATE 8: AWAITING_PROD_APPROVAL (👤 HUMAN GATE)

```
┌─────────────────────────────────────────────────────────────────────────┐
│ PipelineInteraction (Human Decision Point)                              │
│                                                                          │
│ TRIGGERED: After staging tests pass                                     │
│                                                                          │
│ NOTIFICATION:                                                           │
│   Channel: Slack / Teams / Email                                        │
│   Question: "Approve deployment to production for JIRA-123?"            │
│   Details:  - PR URL                                                    │
│             - Test results                                              │
│             - Code changes summary                                      │
│   Timeout:  4 hours                                                     │
│                                                                          │
│ HUMAN RESPONSES:                                                        │
│   ✅ Approve  → STATE 9: PROD                                           │
│   ❌ Reject   → STATE 11: FAILED                                        │
│   ⏰ Timeout  → STATE 13: BLOCKED                                       │
│                                                                          │
│ TRACKING: Stores who approved, when, and response time                  │
└─────────────────────────────────────────────────────────────────────────┘
```

### STATE 9-10: PROD → DONE

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Production Deployment                                                   │
│                                                                          │
│ PROD:  - Merge PR to main branch                                        │
│        - Deploy to production                                           │
│        - Monitor health checks                                          │
│        - Track error rates                                              │
│                                                                          │
│ ROLLBACK CONDITIONS:                                                    │
│   - Error rate > 5%                                                     │
│   - Response time p95 > 3000ms                                          │
│   - Health check fails > 3                                              │
│                                                                          │
│ IF SUCCESSFUL:                                                          │
│   Status: DONE ✅                                                       │
│   Record completion time, total cost, total tokens                      │
│                                                                          │
│ IF FAILURE:                                                             │
│   Status: ROLLED_BACK                                                   │
│   Create incident ticket                                                │
│   Notify on-call team                                                   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 📦 Data Model (What Gets Stored)

```
PipelineExecution (Main Record)
├─ id: 123
├─ ticket_id: "JIRA-456"
├─ ticket_system: "jira"
├─ ticket_title: "Add OAuth2 authentication"
├─ ticket_description: "Implement OAuth2..."
├─ status: new → clarifying → planning → implementing → ... → done
├─ priority: critical | high | medium | low
├─ total_cost: $1.16 (running total)
├─ total_tokens_used: 50,000 (running total)
├─ pr_url: "https://github.com/org/repo/pull/789"
├─ branch_name: "pipeline/JIRA-456-oauth"
├─ started_at: 2025-01-29 10:00:00
├─ completed_at: 2025-01-29 10:23:45
├─ duration: 23m 45s
│
├─ Has Many: AgentExecutions (4 records)
│   ├─ ClarifierAgent: status=completed, tokens=2000, cost=$0.02
│   ├─ PlannerAgent: status=completed, tokens=5000, cost=$0.15
│   ├─ CoderAgent: status=completed, tokens=10000, cost=$0.75
│   └─ ReviewerAgent: status=completed, tokens=8000, cost=$0.24
│
├─ Has Many: PipelineArtifacts (files generated)
│   ├─ clarifications.json (2KB)
│   ├─ plan.md (15KB)
│   ├─ test_spec.yaml (5KB)
│   ├─ generated_code.md (45KB)
│   └─ review_report.json (8KB)
│
├─ Has Many: PipelineEvents (audit trail)
│   ├─ ticket.intake (source: system)
│   ├─ ticket.clarified (source: agent)
│   ├─ plan.ready (source: agent)
│   ├─ pr.opened (source: agent)
│   ├─ pr.approved (source: agent)
│   ├─ cua.dev_passed (source: agent)
│   ├─ cua.staging_passed (source: agent)
│   ├─ human.approved (source: human)
│   └─ prod.promoted (source: system)
│
└─ Has Many: PipelineInteractions (human Q&A)
    ├─ Clarification request (status: answered, 15m response)
    └─ Prod approval (status: answered, 2h response)
```

---

## ⚙️ Background Job Processing (SolidQueue)

```
┌──────────────────────────────────────────────────────────────────┐
│ Queue: pipeline (Priority 10 - Highest)                          │
│                                                                   │
│ ProcessPipelineJob                                               │
│   ├─ Triggered: Every state change                               │
│   ├─ Runs: Pipeline::Orchestrator                                │
│   ├─ Does:                                                        │
│   │   ├─ Check current state                                     │
│   │   ├─ Determine next action                                   │
│   │   ├─ Schedule appropriate agent                              │
│   │   └─ Handle errors and retries                               │
│   └─ Reschedules: Self after agent completes                     │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ Queue: agents (Priority 8)                                       │
│                                                                   │
│ AgentExecutionJob                                                │
│   ├─ Triggered: By ProcessPipelineJob                            │
│   ├─ Does:                                                        │
│   │   ├─ Load agent class (Clarifier/Planner/Coder/Reviewer)     │
│   │   ├─ Initialize workspace if needed                          │
│   │   ├─ Call Claude via BedrockService                          │
│   │   ├─ Save artifacts                                          │
│   │   ├─ Update agent_execution status                           │
│   │   └─ Trigger ProcessPipelineJob (next step)                  │
│   └─ Retry: 3x with exponential backoff                          │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ Queue: notifications (Priority 6)                                │
│                                                                   │
│ NotificationJob                                                  │
│   ├─ Triggered: State changes, human gates                       │
│   ├─ Sends: Slack/Teams/Email notifications                      │
│   └─ Includes: Status updates, approval requests                 │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ Queue: maintenance (Priority 2)                                  │
│                                                                   │
│ TicketWatcherJob (Recurring: every 5 minutes)                    │
│   ├─ Polls: JIRA/Azure DevOps for new tickets                    │
│   ├─ Creates: PipelineExecution for new tickets                  │
│   └─ Triggers: ProcessPipelineJob                                │
│                                                                   │
│ CleanupWorkspacesJob (Recurring: every hour)                     │
│   ├─ Finds: Workspaces older than 24 hours                       │
│   ├─ Deletes: /tmp/pipeline-{id}/ directories                    │
│   └─ Logs: Disk space freed                                      │
│                                                                   │
│ HealthCheckConnectionsJob (Recurring: every 15 minutes)          │
│   ├─ Tests: All MCP connections                                  │
│   └─ Updates: Connection health status                           │
└──────────────────────────────────────────────────────────────────┘
```

---

## 🎯 State Machine (14 States)

```
┌───────────────────────────────────────────────────────────────┐
│                    State Transitions                          │
└───────────────────────────────────────────────────────────────┘

NEW
 ├─ ticket.intake → CLARIFYING
 └─ error → FAILED

CLARIFYING
 ├─ ticket.clarified → PLANNING
 ├─ ticket.needs_clarification → BLOCKED
 └─ error → FAILED

PLANNING
 ├─ plan.ready → IMPLEMENTING
 ├─ clarification_needed → CLARIFYING
 └─ error → FAILED

IMPLEMENTING
 ├─ pr.opened → REVIEW
 └─ error → FAILED

REVIEW
 ├─ pr.approved → TESTING
 ├─ pr.needs_changes → IMPLEMENTING
 └─ error → FAILED

TESTING
 ├─ tests.passed → DEV
 ├─ tests.failed → IMPLEMENTING
 └─ error → FAILED

DEV
 ├─ cua.dev_passed → STAGING
 ├─ cua.failed → FAILED
 └─ error → ROLLED_BACK

STAGING
 ├─ cua.staging_passed → AWAITING_PROD_APPROVAL
 ├─ cua.failed → FAILED
 └─ error → ROLLED_BACK

AWAITING_PROD_APPROVAL
 ├─ human.approved → PROD
 ├─ human.rejected → FAILED
 ├─ timeout → BLOCKED
 └─ error → FAILED

PROD
 ├─ prod.promoted → DONE
 └─ rollback.triggered → ROLLED_BACK

DONE (Terminal)
 └─ (No further transitions)

FAILED (Terminal - can retry)
 └─ retry → NEW

ROLLED_BACK (Terminal - can retry)
 └─ retry → NEW

BLOCKED (Requires resolution)
 ├─ interaction.answered → CLARIFYING
 └─ timeout_resolved → FAILED
```

---

## 💰 Cost Breakdown

### Per Ticket Cost

```
┌────────────────────────────────────────────────────────────────┐
│ Agent            Model           Tokens    Cost      %         │
├────────────────────────────────────────────────────────────────┤
│ ClarifierAgent   Haiku 3.5       ~2,000    $0.02    2%        │
│ PlannerAgent     Sonnet 4.5      ~5,000    $0.15   13%        │
│ CoderAgent       Sonnet 4.5     ~10,000    $0.75   65%        │
│ ReviewerAgent    Sonnet 3.5      ~8,000    $0.24   20%        │
├────────────────────────────────────────────────────────────────┤
│ TOTAL PER TICKET                ~25,000    $1.16  100%        │
└────────────────────────────────────────────────────────────────┘
```

### Monthly Projections

```
Assumptions:
  - 10 tickets per day
  - 22 working days per month
  - 220 tickets per month

Monthly Cost:
  - AI (Claude): 220 × $1.16 = $255
  - Infrastructure: $0 (uses existing AMOS infra)
  - Total: $255/month

Annual Cost:
  - AI: $3,060
  - Infrastructure: $0
  - Total: $3,060/year

ROI:
  - Developer time saved: ~73 hours/month (20 min per ticket)
  - At $100/hour: $7,300/month saved
  - Net savings: $7,045/month
```

---

## 🔍 Real-World Example

### Ticket: "Add OAuth2 Authentication"

**Timeline: 23 minutes, $1.16 total cost**

```
00:00 - Ticket created in JIRA
        └─ TicketWatcherJob picks it up

00:01 - STATE: NEW → CLARIFYING
        └─ ClarifierAgent analyzes ticket
        └─ Requirements: Clear ✅
        └─ Cost: $0.02, Tokens: 2,000

00:02 - STATE: CLARIFYING → PLANNING
        └─ PlannerAgent creates plan:
            • Add OAuth2 gem
            • Create OauthController
            • Update User model
            • Add routes
            • Create tests
        └─ Cost: $0.15, Tokens: 5,000

00:05 - STATE: PLANNING → IMPLEMENTING
        └─ CoderAgent:
            [00:05] Creates workspace
            [00:06] Clones repo
            [00:07] Creates branch: pipeline/JIRA-123-oauth
            [00:08] Generates code:
                    - config/initializers/oauth.rb
                    - app/controllers/oauth_controller.rb
                    - app/models/user.rb (updated)
                    - config/routes.rb (updated)
                    - spec/controllers/oauth_controller_spec.rb
            [00:15] Commits: "Implement OAuth2 authentication"
            [00:16] Pushes to GitHub
            [00:17] Creates PR #789
            [00:18] Cleanup workspace
        └─ Cost: $0.75, Tokens: 10,000

00:18 - STATE: IMPLEMENTING → REVIEW
        └─ ReviewerAgent:
            [00:18] Fetches PR diff
            [00:19] Security check: ✅ No hardcoded secrets
            [00:19] Code quality: ✅ Follows patterns
            [00:20] Tests: ✅ Coverage adequate
            [00:20] Decision: APPROVED ✅
        └─ Cost: $0.24, Tokens: 8,000

00:20 - STATE: REVIEW → TESTING → DEV → STAGING
        └─ Tests pass ✅

00:21 - STATE: STAGING → AWAITING_PROD_APPROVAL
        └─ Slack notification sent to #deployments
        └─ "Approve OAuth2 PR #789 for production?"

02:15 - Human clicks "Approve" in Slack (1h 54m response time)

02:15 - STATE: AWAITING_PROD_APPROVAL → PROD
        └─ PR merged to main
        └─ Deployed to production
        └─ Health checks: ✅ Passing

02:23 - STATE: PROD → DONE ✅
        └─ Total duration: 23 minutes (active) + 1h 54m (waiting)
        └─ Total cost: $1.16
        └─ Total tokens: 25,000
        └─ Files changed: 5
        └─ PR: https://github.com/org/repo/pull/789
```

---

## 🔐 Security & Isolation

### Workspace Isolation

```
/tmp/pipeline-workspaces/
  └─ 123-clarifier/          (permissions: 0700)
      └─ (usually empty - clarifier doesn't need files)

  └─ 123-planner/            (permissions: 0700)
      └─ plan.md
      └─ test_spec.yaml

  └─ 123-coder/              (permissions: 0700)
      └─ repo/               (git clone)
          ├─ .git/
          ├─ app/
          ├─ config/
          └─ spec/

  └─ 123-reviewer/           (permissions: 0700)
      └─ review_notes.md

Auto-cleanup: After 24 hours by CleanupWorkspacesJob
```

### Credential Management

```
MCPConnection
  ├─ encrypted_config (encrypted JSON)
  │   └─ Contains API tokens, passwords
  │   └─ Encrypted with Rails.application.credentials.secret_key_base
  │
  └─ Never logged or exposed in artifacts
  └─ Decrypted only when needed by agents
  └─ Never committed to git
```

### Secrets Scanning

```
ReviewerAgent checks for:
  ✓ No hardcoded API keys
  ✓ No passwords in code
  ✓ No AWS credentials
  ✓ No database credentials
  ✓ No private keys
  ✓ Uses .env or Rails credentials
```

---

## 📊 Monitoring & Observability

### Admin Dashboard

```
/admin/pipeline/executions

Stats Cards:
  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
  │   Total     │  │   Active    │  │  Completed  │  │Total Cost   │
  │    156      │  │      3      │  │     142     │  │  $180.96    │
  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘

Filters:
  Status: [All] [New] [Clarifying] [Planning] [Implementing] ...
  Priority: [All] [Critical] [High] [Medium] [Low]
  System: [All] [JIRA] [Azure DevOps]

Table:
  Ticket     | Title           | Status       | Priority | Cost   | Duration
  JIRA-123   | Add OAuth2      | done         | high     | $1.16  | 23m
  JIRA-124   | Fix payments    | implementing | critical | $0.45  | 5m
  JIRA-125   | Update UI       | review       | medium   | $0.92  | 18m
```

### Execution Detail View

```
/admin/pipeline/executions/123

Overview:
  Ticket: JIRA-123 - "Add OAuth2 authentication"
  Status: done ✅
  Duration: 23m 45s
  Cost: $1.16
  Tokens: 25,000
  PR: https://github.com/org/repo/pull/789

Agent Timeline:
  ┌────────────────────────────────────────────────────────────┐
  │ 10:00 ClarifierAgent  ✅ completed  $0.02  2,000 tokens    │
  │ 10:01 PlannerAgent    ✅ completed  $0.15  5,000 tokens    │
  │ 10:05 CoderAgent      ✅ completed  $0.75 10,000 tokens    │
  │ 10:18 ReviewerAgent   ✅ completed  $0.24  8,000 tokens    │
  └────────────────────────────────────────────────────────────┘

Artifacts:
  📄 clarifications.json (2KB)
  📄 plan.md (15KB)
  📄 test_spec.yaml (5KB)
  📄 generated_code.md (45KB)
  📄 review_report.json (8KB)

Events (10):
  10:00:05 ticket.intake (system)
  10:01:23 ticket.clarified (agent)
  10:02:45 plan.ready (agent)
  10:17:32 pr.opened (agent)
  10:20:15 pr.approved (agent)
  12:15:00 human.approved (human - John Doe)
  12:23:45 prod.promoted (system)

Interactions (1):
  12:15 Production Approval (answered by John Doe in 1h 54m)
```

---

## 🚨 Error Handling & Recovery

### Retry Strategy

```
Job Failures:
  Max retries: 3
  Backoff: Exponential (1s, 5s, 25s)

Agent Failures:
  Automatic retry: Up to 2 times
  Then: Mark as failed

State Machine:
  From any state → FAILED (on unrecoverable error)
  From FAILED → NEW (when manually retried)
```

### Human Intervention Points

```
1. Clarification Needed (BLOCKED)
   └─ Timeout: 2 hours
   └─ Escalation: Manager
   └─ Action: Answer questions

2. Production Approval (AWAITING_PROD_APPROVAL)
   └─ Timeout: 4 hours
   └─ Escalation: On-call team
   └─ Action: Approve/Reject deployment

3. Failed Pipeline
   └─ Notification: Immediate (Slack/Email)
   └─ Action: Review logs, retry if transient

4. Blocked Pipeline
   └─ Notification: After 30 minutes
   └─ Action: Resolve interaction, manually advance state
```

### Rollback Triggers

```
Automatic Rollback if:
  - Error rate > 5% (over 5 minute window)
  - Response time p95 > 3000ms
  - Health check consecutive failures > 3

Rollback Process:
  1. Revert to previous deployment
  2. Update status: ROLLED_BACK
  3. Create incident ticket
  4. Notify on-call team (PagerDuty)
  5. Block further deployments
  6. Require RCA before retry
```

---

## 🎉 Summary

The AI Development Pipeline is a **fully autonomous system** that:

1. **Watches** for new tickets in JIRA/Azure DevOps
2. **Clarifies** requirements with stakeholders
3. **Plans** the implementation approach
4. **Codes** the solution and opens PRs
5. **Reviews** code for quality and security
6. **Tests** in dev/staging environments
7. **Deploys** to production (with human approval)

**With complete visibility:**
- Real-time status tracking
- Cost and token usage monitoring
- Full audit trail
- Human gates at critical points
- Automatic rollback on failure

**All for ~$1.16 per ticket and 23 minutes of processing time!** 🚀

---

## 📚 Related Documentation

- [AI_PIPELINE_IMPLEMENTATION_SUMMARY.md](AI_PIPELINE_IMPLEMENTATION_SUMMARY.md) - Implementation details
- [AI_PIPELINE_SPEC.md](AI_PIPELINE_SPEC.md) - Full specification
- Admin UI: http://localhost:3000/admin/pipeline/connections
- Dashboard: http://localhost:3000/admin/pipeline/executions
