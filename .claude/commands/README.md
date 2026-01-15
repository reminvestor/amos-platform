# Claude Code Commands

Quick access commands that chain multiple skills together for common workflows.

## Primary Commands (Use These)

### Environment & Health

#### `/check-deployment`
Comprehensive health checks for all environments (dev, staging, production).

**When to use:**
- Daily health check before starting work
- Debugging connection issues (Docker, database, Redis)
- Checking deployed application status
- Verifying all services are running

**Example:**
```bash
/check-deployment
```

#### `/prepare-dev-env`
Complete setup of development environment from scratch.

**When to use:**
- Fresh developer onboarding (first time setup)
- New machine setup
- Major dependency updates (Ruby/gem changes)
- Recovering from corrupted environment
- Complete reset needed

**Example:**
```bash
/prepare-dev-env
```

---

### Planning & Design

#### `/brainstorm [topic]`
Interactive design refinement through Socratic questioning.

**When to use:**
- Starting a new feature and need to clarify requirements
- Exploring implementation approaches
- Identifying edge cases and trade-offs

**Example:**
```bash
/brainstorm subscription billing
```

#### `/write-plan [feature]`
Break down features into atomic 2-5 minute tasks.

**When to use:**
- After brainstorming, before implementation
- Complex features needing structure
- Want systematic execution tracking

**Example:**
```bash
/write-plan subscription management with Stripe
```

#### `/execute-plan`
Systematic plan execution with checkpoints.

**When to use:**
- After `/write-plan` to begin implementation
- Working through complex feature plans
- Need structured progress tracking

**Example:**
```bash
/execute-plan
```

---

### Feature Development

#### `/complete-feature [feature_name]` ⭐ PRIMARY COMMAND
End-to-end feature development with mandatory UX review and testing.

**Includes:**
1. Scaffolds the feature (model, controller, routes)
2. Creates Scout AI tools (if needed)
3. Creates V2 workflow templates (if needed)
4. **Runs UX review on all new views**
5. **Writes comprehensive system tests**
6. **Reloads Docker for live manual testing**
7. Full pre-commit checks (linting, tests, docs)
8. Creates draft PR on GitHub

**When to use:**
- Building any new feature
- The default command for feature development
- When you want quality built-in from the start

**Example:**
```bash
/complete-feature "subscription management"
```

---

### Git & GitHub

#### `/github-push [pr-title]`
Push to GitHub and create a draft pull request.

**When to use:**
- After using `/complete-feature` (PR creation is automated)
- For manual pushes if needed

**Example:**
```bash
/github-push "Add subscription management feature"
```

#### `/code-review [mode]`
Pre-commit review checklist and PR feedback processing.

**Modes:**
- `request` - Pre-commit self-review checklist (default)
- `receive [pr-number]` - Process PR feedback systematically
- `quick` - Fast style check only

**When to use:**
- Before pushing code (catches issues early)
- After receiving PR feedback
- Self-review before team review

**Example:**
```bash
/code-review              # Full pre-commit review
/code-review receive 123  # Process PR #123 feedback
```

---

## Advanced/Specialized Commands

Use these only when you need to work outside the standard feature workflow.

---

#### `/add-tool [description]`
Create a new Scout AI tool without building a full feature.

**When to use:**
- Adding tools to existing features
- Building tools independently

```bash
/add-tool "Export campaign data to CSV"
```
#### `/add-workflow [description]`
Create a new V2 workflow template without building a full feature.

**When to use:**
- Adding workflows to existing features
- Building workflows independently

```bash
/add-workflow "Auto-renew subscriptions"
```

#### `/add-integration [service_name]`
Set up a new external API integration.

**When to use:**
- Connecting to external services (Stripe, Mailgun, etc.)

```bash
/add-integration "Shopify"
```

#### `/add-entity [name]`
Create test entities with sample data.

**When to use:**
- Setting up test tenants for development
- Creating demo data

```bash
/add-entity "Test Company"
```

#### `/ux [file_paths]`
Review UX implementation and provide Rails + Bootstrap best practice recommendations.

**When to use:**
- Manual UX reviews (already runs in `/complete-feature`)
- Reviewing existing code

```bash
/ux app/views/scout/index.html.erb app/assets/stylesheets/scout.scss
```

#### `/validate-skill [skill_name]`
Validate and test skill definitions for correctness.

**When to use:**
- Creating or modifying skills
- Debugging skill issues

```bash
/validate-skill
```

---

## Infrastructure & Database

#### `/docker`
Manage Docker containers for development environment.

**When to use:**
- Start/stop services
- View logs
- Execute commands in containers
- Reset containers

```bash
/docker
```

#### `/reset-database`
Reset the demo database to initial state.

**When to use:**
- Starting fresh with clean data
- Recovering from failed migrations
- Cleaning up after integration testing

```bash
/reset-database
```

#### `/db-snapshot`
Create and manage database snapshots for backup and testing.

**When to use:**
- Backup before risky operations
- Testing with consistent data
- Comparing database states

```bash
/db-snapshot
```

#### `/test-rag`
Test RAG (Retrieval-Augmented Generation) system.

**When to use:**
- Testing document indexing
- Verifying semantic search
- Testing multi-tenant isolation

```bash
/test-rag
```

---

## Command Cheatsheet

| Task | Command | Use When |
|------|---------|----------|
| **Build complete feature** | **`/complete-feature`** | **Building any new feature** |
| Brainstorm ideas | `/brainstorm` | Clarify requirements, explore approaches |
| Create task plan | `/write-plan` | Break down complex features |
| Execute plan | `/execute-plan` | Systematic implementation |
| Pre-commit review | `/code-review` | Before pushing code |
| Check system health | `/check-deployment` | Starting work, debugging issues |
| Setup dev environment | `/prepare-dev-env` | First time setup, corrupted env |
| Push to GitHub | `/github-push` | Need to push manually |
| Manage Docker | `/docker` | Container issues, logs |
| Reset database | `/reset-database` | Need fresh data |
| Create Scout tool | `/add-tool` | Need tools outside `/complete-feature` |
| Create workflow | `/add-workflow` | Need workflows outside `/complete-feature` |
| UX review | `/ux` | Manual UX reviews |

---

## Daily Workflow

### Morning: Start Work
```bash
/check-deployment              # Verify everything is healthy
```

### Building a Feature
```bash
/complete-feature "feature name"  # One command that does it all:
                                  # - Scaffolds feature
                                  # - Adds tools (if needed)
                                  # - UX review (mandatory)
                                  # - Tests (mandatory)
                                  # - Docker reload (manual testing)
                                  # - Final checks
                                  # - Creates PR
```

### Troubleshooting
```bash
/check-deployment              # See what's broken
/reset-database               # Hard reset corrupted data
/prepare-dev-env              # Complete environment reset
/docker                       # Check/restart services
```

---

## Philosophy

**Simple First, Advanced When Needed**

- Use `/complete-feature` for 95% of your feature work
- Use specialized commands only when you need to work outside that workflow
- All checks (UX, tests, linting) are mandatory in `/complete-feature`
- Manual testing in Docker happens BEFORE pushing to GitHub

---

## Creating Custom Commands

Commands are just markdown files in `.claude/commands/`:

```markdown
# My Custom Command

Description of what it does.

## Usage

\`\`\`
/my-custom-command [args]
\`\`\`

## What It Does

- Step 1
- Step 2
```

Then use with: `/my-custom-command`

---

## Resources

- [Skills Usage Guide](../.claude/docs/skills-usage-guide.md)
- [Compound Skills Guide](../.claude/docs/compound-skills-guide.md)
- [Individual Skills](../.claude/skills/)
