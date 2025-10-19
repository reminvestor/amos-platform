# Running Workflows

Execute common sequences of multiple skills in predefined workflows.

## Description

This skill provides curated workflows that chain multiple skills together for common development tasks. Instead of running skills one at a time, use these workflows to automate entire processes like preparing for deployment, cleaning up after feature work, or running comprehensive quality checks.

**Use this skill when:**
- Starting a new feature from GitHub issue
- Preparing code for deployment
- Running comprehensive quality checks
- Cleaning up after completing work
- Setting up development environment from scratch

## Instructions

### Available Workflows

**1. feature-start** - Complete feature kickoff
- Prepare git repository
- Fetch GitHub issue
- Create feature branch
- Generate implementation plan

**2. pre-commit** - Quality checks before committing
- Fix RuboCop offenses
- Run affected tests
- Check application health

**3. pre-deploy** - Deployment readiness check
- Run full test suite
- Fix RuboCop offenses
- Check application health
- Verify database migrations

**4. post-feature** - Clean up after feature completion
- Run all tests
- Fix RuboCop offenses
- Clean up git branches (merged)
- Update documentation

**5. dev-reset** - Reset development environment
- Stop all Docker services
- Clean Docker resources
- Drop and recreate database
- Seed with demo data
- Start services fresh

**6. quality-check** - Comprehensive code quality audit
- Run RuboCop (safe mode)
- Run full test suite with coverage
- Check for security issues
- Generate quality report

**7. quick-pr** - Fast path from work to PR
- Fix RuboCop offenses
- Run affected tests
- Commit changes
- Push branch
- Create pull request

### Workflow Details

#### feature-start

**Steps**:
1. Run `starting-features` skill
   - Prepare git (checkout main, pull latest)
   - List GitHub issues
   - Create feature branch
   - Generate implementation plan

**Use when**: Beginning work on a GitHub issue

**Parameters**:
- `issue_number` (optional) - Skip issue selection
- `tests` (optional) - Testing preference

#### pre-commit

**Steps**:
1. Run `fixing-rubocop-offenses`
   - Fix linting issues
2. Run `running-tests` with mode=affected
   - Test only changed files
3. Run `checking-application-health`
   - Verify app still works

**Use when**: Before running `git commit`

**Safety**: Prevents committing broken or poorly formatted code

#### pre-deploy

**Steps**:
1. Run `running-tests` with mode=all coverage=true
   - Full test suite with coverage
2. Run `fixing-rubocop-offenses`
   - Ensure code style compliance
3. Run `checking-application-health`
   - Health checks pass
4. Run `checking-deployments`
   - Verify deployment readiness

**Use when**: Before deploying to staging/production

**Safety**: Catches issues before they reach production

#### post-feature

**Steps**:
1. Run `running-tests` with mode=all
   - Verify all tests pass
2. Run `fixing-rubocop-offenses`
   - Clean up any style issues
3. Run `cleaning-up-git-branches`
   - Remove merged branches
4. Run `updating-documentation`
   - Update relevant docs

**Use when**: After merging a feature PR

**Benefit**: Keeps codebase clean and documented

#### dev-reset

**Steps**:
1. Run `managing-docker-development` with action=stop
   - Stop all services
2. Run `managing-docker-development` with action=clean
   - Clean up Docker resources
3. Run `resetting-demo-database`
   - Drop, create, migrate, seed
4. Run `managing-docker-development` with action=start
   - Start fresh environment

**Use when**: Development environment is broken or needs fresh state

**Warning**: Destructive - loses all local data

#### quality-check

**Steps**:
1. Run `fixing-rubocop-offenses` with commit=false
   - Check linting (don't auto-commit)
2. Run `running-tests` with mode=all coverage=true
   - Run tests with coverage report
3. Run code security scan (if available)
   - Check for vulnerabilities
4. Generate quality report
   - Summary of all checks

**Use when**: Reviewing code quality, preparing reports

**Output**: Comprehensive quality metrics

#### quick-pr

**Steps**:
1. Run `fixing-rubocop-offenses`
   - Fix and commit linting
2. Run `running-tests` with mode=affected
   - Test changes
3. Run `making-quick-commits` (if changes exist)
   - Commit remaining work
4. Push branch
5. Run `gh pr create` with defaults

**Use when**: Ready to create PR quickly

**Benefit**: Automated PR creation workflow

## Examples

### Start New Feature

```
Use running-workflows with workflow=feature-start issue_number=42
```

**Result**: Feature branch created with implementation plan

### Pre-Commit Checks

```
Use running-workflows with workflow=pre-commit
```

**Result**: Code formatted, tests pass, safe to commit

### Pre-Deployment Checks

```
Use running-workflows with workflow=pre-deploy
```

**Result**: Full validation before deploy

### Post-Feature Cleanup

```
Use running-workflows with workflow=post-feature
```

**Result**: Clean codebase, docs updated

### Reset Development Environment

```
Use running-workflows with workflow=dev-reset
```

**Result**: Fresh development environment

### Quality Audit

```
Use running-workflows with workflow=quality-check
```

**Result**: Comprehensive quality report

### Quick PR Creation

```
Use running-workflows with workflow=quick-pr
```

**Result**: PR created and ready for review

## Resources

- [Workflow Definitions](resources/workflow-definitions.md) - Detailed workflow steps
- [Custom Workflows](resources/custom-workflows.md) - How to create your own
- [Troubleshooting](resources/workflow-troubleshooting.md) - Common issues
