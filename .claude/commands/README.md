# Claude Code Commands

Quick access commands that chain multiple skills together for common workflows.

## Available Commands

### Development Setup

#### `/new-dev-setup [entity_name]`
Complete onboarding for new developers.

**What it does:**
- Checks application health
- Sets up entity with full sample data
- Runs tests to validate setup
- Shows getting started guide

**Example:**
```bash
/new-dev-setup "Training Company"
```

**Uses skills:** checking-application-health, preparing-development-environment, running-tests

---

### Code Quality & Commits

#### `/quick-commit [message]`
Fast pre-commit workflow for small changes.

**What it does:**
- Runs quick tests (changed files only)
- Fixes RuboCop offenses
- Commits with message
- Ready to push

**Example:**
```bash
/quick-commit "Fix validation bug"
```

**Uses skills:** running-tests (quick), fixing-rubocop-offenses, making-quick-commits

#### `/finishing-feature-work`
Full pre-commit workflow before creating PR.

**What it does:**
- Runs full test suite
- Fixes all RuboCop offenses
- Cleans up merged branches
- Updates documentation
- Optional auto-commit

**Example:**
```bash
# Run all checks
Use finishing-feature-work

# Skip docs update during development
Use finishing-feature-work with skip_docs=true

# Auto-commit if all passes
Use finishing-feature-work with auto_commit=true
```

**Uses skills:** running-tests, fixing-rubocop-offenses, cleaning-up-git-branches, updating-documentation

---

### Testing

#### `/test-feature [workflow_name]`
Comprehensive feature testing workflow.

**What it does:**
- Tests all Scout AI tools
- Tests specific workflow (if provided)
- Runs full test suite
- Generates summary report

**Example:**
```bash
/test-feature create_campaign
```

**Uses skills:** testing-tools-manually, testing-workflows-manually, running-tests

---

### Feature Development

#### `/build-feature [feature_name]`
Scaffold new feature with proper patterns.

**What it does:**
- Creates model with entity scoping
- Generates migration
- Creates controller with authentication
- Adds routes
- Generates tests
- Creates Scout AI tool (optional)

**Example:**
```bash
/build-feature "subscription"
```

**Uses skills:** starting-features

#### `/add-tool [tool_name]`
Create new Scout AI tool.

**What it does:**
- Generates tool file from template
- Adds to tool catalog
- Creates test file
- Shows usage examples

**Example:**
```bash
/add-tool "send_sms"
```

**Uses skills:** starting-features

#### `/add-workflow [workflow_name]`
Create new V2 workflow template.

**What it does:**
- Generates YAML template
- Sets up three-phase structure
- Adds keywords
- Creates test script

**Example:**
```bash
/add-workflow "create_landing_page"
```

**Uses skills:** starting-features

#### `/add-integration [service_name]`
Add new external integration.

**What it does:**
- Creates Integration record
- Generates IntegrationOperation definitions
- Adds authentication handling
- Creates test suite

**Example:**
```bash
/add-integration "Stripe"
```

**Uses skills:** starting-features

---

## Command vs Skill

**Commands** = Quick shortcuts that chain multiple skills
**Skills** = Individual reusable capabilities

### When to use Commands:
- Common workflows you repeat often
- Multi-step processes
- Onboarding new developers
- Pre-commit checks

### When to use Skills directly:
- Single-purpose tasks
- Custom parameters needed
- Learning the system
- Building custom workflows

## Creating Custom Commands

Commands are just markdown files in `.claude/commands/`:

```markdown
# My Custom Command

Description of what it does.

## Usage

\`\`\`
/my-custom-command [args]
\`\`\`

## Implementation

\`\`\`bash
#!/usr/bin/env bash
# Chain skills together
.claude/skills/skill-one/scripts/script.sh
.claude/skills/skill-two/scripts/script.sh
\`\`\`
```

Then use with: `/my-custom-command`

## Command Cheatsheet

| Task | Command | Speed | Thoroughness |
|------|---------|-------|--------------|
| New dev setup | `/new-dev-setup` | Slow | Complete |
| Quick fix commit | `/quick-commit "fix"` | Fast | Basic |
| Pre-PR checks | `finishing-feature-work` | Medium | Complete |
| Test feature | `/test-feature` | Slow | Complete |
| Build feature | `/build-feature` | Fast | Scaffold |

## Tips

1. **Use quick-commit during development**
   - Fast iteration
   - Only tests changed files
   - Good for bug fixes

2. **Use finishing-feature-work before PR**
   - Full test coverage
   - Complete checks
   - Documentation updated

3. **Chain commands for complex workflows**
   ```bash
   /build-feature "payments" && \
   /test-feature "payment_workflow" && \
   finishing-feature-work
   ```

4. **Create project-specific commands**
   - Add to `.claude/commands/`
   - Name with your workflow
   - Share with team

## Resources

- [Skills Usage Guide](../.claude/docs/skills-usage-guide.md)
- [Compound Skills Guide](../.claude/docs/compound-skills-guide.md)
- [Individual Skills](../.claude/skills/)
