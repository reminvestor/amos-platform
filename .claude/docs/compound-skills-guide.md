# Compound Skills Guide

Commonly-used skills that chain multiple operations together.

## Overview

Compound skills orchestrate multiple tasks in a single command, making common workflows faster and more reliable. They follow best practices and ensure consistency across development activities.

## Available Compound Skills

### 1. Preparing Development Environment

**Skill:** `preparing-development-environment`

**Purpose:** Complete environment setup from zero to ready-to-code

**What it does:**
- Verifies Docker and database health
- Runs database migrations
- Creates test entity with sample data
- Updates documentation
- Provides access URLs and credentials

**Common usage:**
```
Use preparing-development-environment with entity_name='Acme Corp'
```

**When to use:**
- First time setup
- Onboarding new developers
- After major changes requiring reset
- Starting new feature work

**Parameters:**
- `entity_name` - Name for test entity (prompts if not provided)
- `skip_entity=true` - Skip entity creation
- `skip_docs=true` - Skip documentation updates

**Output:**
- Entity ID and subdomain
- Admin credentials
- Access URLs
- Sample data summary

---

### 2. Finishing Feature Work

**Skill:** `finishing-feature-work`

**Purpose:** Pre-commit quality assurance workflow

**What it does:**
- Runs full test suite
- Fixes RuboCop offenses automatically
- Cleans up merged git branches
- Updates documentation
- Prepares for commit/PR

**Common usage:**
```
Use finishing-feature-work
```

**When to use:**
- Before committing changes
- Before creating pull requests
- After finishing feature development
- Before pushing to remote

**Parameters:**
- `skip_tests=true` - Skip test suite (NOT RECOMMENDED)
- `skip_docs=true` - Skip documentation updates
- `skip_cleanup=true` - Skip branch cleanup
- `auto_commit=true` - Auto-commit if all checks pass

**Exit behavior:**
- Exit 0: All checks passed, ready to commit
- Exit 1: Issues detected, fix before committing

---

## Usage Patterns

### New Feature Development

```bash
# 1. Start with clean environment
Use preparing-development-environment with entity_name='Feature Testing'

# 2. Develop feature...
# (write code, make changes)

# 3. Before committing
Use finishing-feature-work
```

### Quick Development Cycle

```bash
# Setup once at start of day
Use preparing-development-environment with skip_docs=true

# During development, quick checks
Use finishing-feature-work with skip_docs=true skip_cleanup=true

# Before final commit
Use finishing-feature-work
```

### New Developer Onboarding

```bash
# Day 1: Full setup with sample data
Use preparing-development-environment with entity_name='Training Entity'

# Result: Working app with test data to explore
# URL: http://training-entity.localhost:3000
# Login: admin@training-entity.test / password123
```

### Pre-PR Workflow

```bash
# Ensure everything is clean and tested
Use finishing-feature-work

# If all passes, create PR
git push
gh pr create
```

## Component Skills

These compound skills use these atomic skills internally:

**Preparing Development Environment uses:**
- `checking-application-health` - Docker and database verification
- `managing-docker-development` - Container orchestration
- `adding-entities` - Entity creation with sample data
- `updating-documentation` - Docs generation

**Finishing Feature Work uses:**
- `running-tests` - Test suite execution
- `fixing-rubocop-offenses` - Code style enforcement
- `cleaning-up-git-branches` - Branch cleanup
- `updating-documentation` - Docs generation

## Benefits of Compound Skills

**Consistency:**
- Everyone follows same workflow
- No missed steps
- Reproducible results

**Efficiency:**
- One command vs many manual steps
- Faster onboarding
- Less context switching

**Quality:**
- Automated checks before commit
- Documentation stays current
- Tests always run

**Best Practices:**
- Encodes team standards
- Easy to update standards centrally
- Self-documenting workflow

## Creating Custom Compound Skills

To create your own compound skill that chains operations:

1. **Create skill directory:**
   ```bash
   mkdir -p .claude/skills/your-compound-skill/{scripts,resources}
   ```

2. **Write SKILL.md** with clear description of workflow

3. **Create orchestration script** in `scripts/`:
   ```bash
   #!/usr/bin/env bash
   # Call multiple atomic scripts or commands
   
   .claude/skills/skill-one/scripts/do-thing.sh
   .claude/skills/skill-two/scripts/do-other.sh
   
   # Or run commands directly
   docker-compose run --rm web rails test
   ```

4. **Add resources** for reference materials

5. **Test the workflow** end-to-end

## Tips

**During Active Development:**
- Use `skip_docs=true` to save time
- Use `skip_cleanup=true` to preserve branches
- Run full workflow before final commit

**For CI/CD:**
- Compound skills can be called in GitHub Actions
- Use non-interactive mode (all params provided)
- Check exit codes for pass/fail

**Customization:**
- Copy compound skill to new name
- Modify script to fit your workflow
- Share with team via git

## Troubleshooting

**Skill fails partway through:**
- Check which step failed in output
- Run that atomic skill individually
- Fix issue and re-run compound skill

**Want different order of operations:**
- Create custom compound skill
- Or run atomic skills individually in desired order

**Need to skip certain steps:**
- Use `skip_*` parameters
- Or run only needed atomic skills directly

## Related Documentation

- [Skills Usage Guide](skills-usage-guide.md) - General skills overview
- [Agent Skills Format](../../skills/building-skills/SKILL.md) - Skill structure
- Individual skill SKILL.md files for details
