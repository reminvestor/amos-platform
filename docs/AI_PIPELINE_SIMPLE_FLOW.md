# AI Development Pipeline - Simple Flow Example

## Real-World Example: "Add User Profile Page"

Let's walk through what happens when a ticket is created in JIRA:

---

## 📋 Starting Point: Ticket Created in JIRA

```
Ticket: PROJ-456
Title: Add user profile page
Description: Users should be able to view and edit their profile information
Status: Ready for Dev
Assignee: (unassigned)
```

---

## 🤖 The AI Pipeline Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. TICKET WATCHER (Every 5 minutes)                                         │
│    Polls JIRA for new tickets in "Ready for Dev"                            │
└────────────────┬────────────────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 2. TICKET FILTERED                                                           │
│    ✅ Status: Ready for Dev                                                 │
│    ✅ Type: Story                                                           │
│    ✅ No blocking labels (not 'blocked', 'manual-only', etc.)               │
│    ✅ Unassigned                                                            │
│    → Pipeline Execution Created (Status: NEW)                               │
└────────────────┬────────────────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 3. CLARIFIER AGENT (Claude 3.5 Haiku - $0.02)                               │
│    Analyzes: "Add user profile page" + description                          │
│                                                                              │
│    🤔 Questions Generated:                                                  │
│    1. [UX] Should profile editing be inline or separate edit mode?          │
│    2. [Technical] What fields: name, email, avatar, bio? Any custom fields? │
│    3. [Security] Who can view profiles - public, authenticated, friends?    │
│                                                                              │
│    → Confidence: 0.65 (needs clarification)                                 │
│    → Posts questions to JIRA comment                                        │
│    → Sends Slack notification to #ai-clarifications                         │
│    → Status: BLOCKED (waiting for human response)                           │
└────────────────┬────────────────────────────────────────────────────────────┘
                 │
                 │ 👤 HUMAN ANSWERS (within 2 hours):
                 │    "Inline editing, fields: name/email/avatar/bio,
                 │     authenticated users only"
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 4. PLANNER AGENT (Claude Sonnet 4.5 - $0.15)                                │
│    Reads: Original ticket + clarifications                                  │
│                                                                              │
│    📝 Plan Generated (plan.md):                                             │
│    ┌──────────────────────────────────────────────────────────────────┐    │
│    │ Files to Create:                                                  │    │
│    │ - app/controllers/profiles_controller.rb                          │    │
│    │ - app/views/profiles/show.html.erb                                │    │
│    │ - app/assets/stylesheets/profiles.scss                            │    │
│    │                                                                    │    │
│    │ Files to Modify:                                                  │    │
│    │ - config/routes.rb (add profile routes)                           │    │
│    │ - app/models/user.rb (add avatar validation)                      │    │
│    │                                                                    │    │
│    │ Tests to Create:                                                  │    │
│    │ - test/controllers/profiles_controller_test.rb                    │    │
│    │ - test/system/user_profile_test.rb                                │    │
│    │                                                                    │    │
│    │ Implementation Steps:                                             │    │
│    │ 1. Add routes for profiles#show and profiles#update              │    │
│    │ 2. Create ProfilesController with show and update actions         │    │
│    │ 3. Create view with inline editing using Stimulus                 │    │
│    │ 4. Add avatar upload with ActiveStorage                           │    │
│    │ 5. Add authorization (ensure user can only edit own profile)      │    │
│    │ 6. Write controller and system tests                              │    │
│    └──────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│    → Status: PLANNING → IMPLEMENTING                                        │
└────────────────┬────────────────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 5. CODER AGENT (Claude Sonnet 4.5 - $0.75)                                  │
│    Reads: plan.md from PlannerAgent                                         │
│                                                                              │
│    🛠️ 11-Step Workflow:                                                     │
│    ┌──────────────────────────────────────────────────────────────────┐    │
│    │ Step 1:  Create workspace /tmp/pipeline-1/coder                   │    │
│    │ Step 2:  Clone repository with credentials                        │    │
│    │ Step 3:  Create branch: pipeline/PROJ-456-1698765432             │    │
│    │ Step 4:  Read plan.md                                             │    │
│    │ Step 5:  Generate complete code with Claude Sonnet 4.5            │    │
│    │ Step 6:  Parse FILE: markers to extract files                     │    │
│    │ Step 7:  Identify test files (test/, spec/)                       │    │
│    │ Step 8-9: Push all files to GitHub (via MCP)                      │    │
│    │ Step 10: Create Pull Request with formatted body                  │    │
│    │ Step 11: Cleanup workspace                                        │    │
│    └──────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│    💻 Code Generated (example from one file):                               │
│    ┌──────────────────────────────────────────────────────────────────┐    │
│    │ FILE: app/controllers/profiles_controller.rb                      │    │
│    │                                                                    │    │
│    │ class ProfilesController < ApplicationController                  │    │
│    │   before_action :authenticate_user!                               │    │
│    │   before_action :authorize_user!, only: [:update]                 │    │
│    │                                                                    │    │
│    │   def show                                                         │    │
│    │     @user = User.find(params[:id])                                │    │
│    │   end                                                              │    │
│    │                                                                    │    │
│    │   def update                                                       │    │
│    │     if current_user.update(profile_params)                        │    │
│    │       redirect_to profile_path(current_user),                     │    │
│    │         notice: "Profile updated successfully"                    │    │
│    │     else                                                           │    │
│    │       render :show, status: :unprocessable_entity                 │    │
│    │     end                                                            │    │
│    │   end                                                              │    │
│    │                                                                    │    │
│    │   private                                                          │    │
│    │                                                                    │    │
│    │   def authorize_user!                                             │    │
│    │     redirect_to root_path unless current_user.id == params[:id]   │    │
│    │   end                                                              │    │
│    │                                                                    │    │
│    │   def profile_params                                              │    │
│    │     params.require(:user).permit(:name, :email, :bio, :avatar)    │    │
│    │   end                                                              │    │
│    │ end                                                                │    │
│    └──────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│    📤 Pull Request Created:                                                 │
│    Title: "Add user profile page (PROJ-456)"                                │
│    URL: https://github.com/yourorg/repo/pull/123                            │
│                                                                              │
│    → Status: IMPLEMENTING → REVIEW                                          │
└────────────────┬────────────────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 6. REVIEWER AGENT (Claude 3.5 Sonnet - $0.24)                               │
│    Fetches: GitHub PR diff                                                  │
│                                                                              │
│    🔍 Security & Quality Checks:                                            │
│    ┌──────────────────────────────────────────────────────────────────┐    │
│    │ ✅ No secrets in code (API keys, passwords)                       │    │
│    │ ✅ No SQL injection vulnerabilities                               │    │
│    │ ✅ Authorization check present (authorize_user!)                  │    │
│    │ ✅ Test coverage >80% (controller + system tests)                 │    │
│    │ ✅ Strong params used (profile_params)                            │    │
│    │ ✅ Follows Rails conventions                                      │    │
│    │ ⚠️  Suggestion: Add rate limiting for profile updates             │    │
│    │ ⚠️  Suggestion: Add avatar size validation                        │    │
│    └──────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│    📊 Review Report (review_report.md):                                     │
│    - Decision: APPROVED with minor suggestions                              │
│    - Posts review comment to GitHub PR                                      │
│                                                                              │
│    → Status: REVIEW → TESTING                                               │
└────────────────┬────────────────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 7. AUTOMATED TESTING                                                        │
│    Runs: All tests on CI/CD                                                 │
│    ✅ 15 tests passed                                                       │
│    ✅ Coverage: 85%                                                         │
│    → Status: TESTING → DEV                                                  │
└────────────────┬────────────────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 8. DEV ENVIRONMENT DEPLOYMENT                                               │
│    Auto-merge to dev branch                                                 │
│    Deploy to dev.yourcompany.com                                            │
│    → Status: DEV → STAGING                                                  │
└────────────────┬────────────────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 9. STAGING ENVIRONMENT DEPLOYMENT                                           │
│    Deploy to staging.yourcompany.com                                        │
│    Run smoke tests                                                          │
│    ✅ All tests passed                                                      │
│    → Status: STAGING → AWAITING_PROD_APPROVAL                               │
└────────────────┬────────────────────────────────────────────────────────────┘
                 │
                 │ 👤 HUMAN GATE #2: Production Approval Required
                 │    Notifications sent to:
                 │    - 📧 Email to release managers
                 │    - 💬 Slack message in #ai-pipeline-approvals
                 │
                 │ Release Manager clicks "Approve" button
                 │ (within 4 hours or escalates)
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 10. PRODUCTION DEPLOYMENT                                                   │
│     Progressive canary rollout:                                             │
│     - 10% of users → monitor for 1 hour                                     │
│     - 50% of users → monitor for 1 hour                                     │
│     - 100% of users → complete                                              │
│                                                                              │
│     🎉 Feature live at: yourcompany.com/profile/123                         │
│                                                                              │
│     → Status: PROD → DONE                                                   │
│                                                                              │
│     📊 Final Metrics:                                                       │
│     - Total time: ~45 minutes (vs 2-4 hours manual)                         │
│     - Total cost: $1.16 in AI tokens                                        │
│     - Human time: 5 min clarifications + 2 min approval = 7 minutes         │
│     - Files created: 5 (controller, view, styles, 2 test files)             │
│     - Tests: 15 passing, 85% coverage                                       │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 📬 Notifications Timeline

```
Time    Event                       Notification
────────────────────────────────────────────────────────────────────────
00:00   Ticket detected             💬 Slack: #ai-pipeline-status
                                    "Started: PROJ-456"

00:03   Clarifier needs answers     💬 Slack: #ai-clarifications
                                    📧 Email: assignee@company.com
                                    💬 JIRA: Comment with questions

01:00   Human answers received      💬 Slack: "Unblocked, continuing..."

01:05   Planner completed           💬 Slack: "Plan ready, generating code"

01:15   Code generated, PR opened   💬 Slack: "PR created: #123"
                                    🔗 Link to GitHub PR

01:20   Code review approved        💬 Slack: "Code approved, tests running"

01:30   Tests passed                💬 Slack: "Deployed to DEV"

01:35   Staging deployment          💬 Slack: "Deployed to STAGING"

01:40   Awaiting approval           💬 Slack: #ai-pipeline-approvals
                                    📧 Email: release-managers@company.com
                                    "Approve for production?"

02:00   Human approves              💬 Slack: "Deploying to production..."

02:45   Production complete         💬 Slack: "✅ PROJ-456 DONE"
                                    💬 JIRA: Ticket transitioned to "Done"
                                    🎉 Celebration emoji
```

---

## 🚫 Failure Scenarios (Auto-Handled)

### Scenario 1: Tests Fail
```
1. CoderAgent creates PR
2. ReviewerAgent approves
3. CI/CD tests run → ❌ 3 tests failed
4. Pipeline: TESTING → FAILED
5. Notification: 🚨 Slack + Email to oncall
6. Human reviews error logs
7. Human fixes manually OR re-triggers pipeline
```

### Scenario 2: Clarification Timeout
```
1. ClarifierAgent posts questions
2. Pipeline: BLOCKED (waiting for human)
3. Timeout: 2 hours elapsed
4. Notification: ⚠️ Slack + Email to manager
5. Manager escalates or answers
```

### Scenario 3: Production Health Check Fails
```
1. Deployed to 10% of users
2. Error rate spikes >5%
3. Auto-rollback triggered
4. Pipeline: PROD → ROLLED_BACK
5. Notification: 🚨 Slack + Email + Create incident ticket
6. Block pipeline for this ticket
7. Require root cause analysis before retry
```

---

## 💰 Cost Breakdown

| Agent | Model | Tokens | Cost |
|-------|-------|--------|------|
| ClarifierAgent | Claude 3.5 Haiku | ~2,000 | $0.02 |
| PlannerAgent | Claude Sonnet 4.5 | ~5,000 | $0.15 |
| CoderAgent | Claude Sonnet 4.5 | ~10,000 | $0.75 |
| ReviewerAgent | Claude 3.5 Sonnet | ~8,000 | $0.24 |
| **Total** | | **~25,000** | **$1.16** |

**Human Time Saved**: 2-4 hours → 7 minutes = 97% reduction

---

## 🎯 Key Takeaways

1. **Fully Automated**: Ticket → Production with only 2 human touchpoints
2. **Fast**: 45 minutes vs 2-4 hours manually
3. **Cheap**: $1.16 per feature
4. **Safe**: Multiple checkpoints (review, tests, staging, approval)
5. **Transparent**: Every step logged, visible in admin UI
6. **Smart**: AI asks clarifying questions when needed
7. **Recoverable**: Auto-rollback on production issues

The AI handles the tedious parts (writing boilerplate, tests, routes) while humans focus on high-value decisions (requirements, architecture, deployment approval).
