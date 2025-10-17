# Checking Deployments

**Pre-deployment checklist: migrations, env vars, breaking changes, tests**

Comprehensive pre-deploy verification to catch issues before they reach production. Validates git status, migrations, tests, linting, security, and more.

## When to Use

- Before merging to main
- Before deploying to staging/production
- After completing a feature
- As final PR review step

## Usage

```bash
# Interactive deployment check
./.claude/skills/checking-deployments/scripts/check-deployment.sh

# Full production check
./.claude/skills/checking-deployments/scripts/check-deployment.sh production

# Staging check with auto-fix
./.claude/skills/checking-deployments/scripts/check-deployment.sh staging --fix
```

## What Gets Checked

1. **Git Status**: Branch, uncommitted changes, sync with origin
2. **Pending Migrations**: New/unsafe migrations
3. **Environment Variables**: Required vars from .env.example
4. **Breaking Changes**: CHANGELOG, removed routes/files
5. **Test Suite**: Full test execution
6. **RuboCop**: Code quality/style
7. **Dependencies**: Security vulnerabilities, outdated gems
8. **Asset Compilation**: Production asset build

## Deployment Readiness Statuses

- 🟢 **READY** (0 issues): All checks passed
- 🟡 **CAUTION** (1-2 issues): Review required
- 🔴 **NOT READY** (3+ issues): Do not deploy

## Script Reference

### `check-deployment.sh [ENVIRONMENT] [--fix]`

**Parameters**:
- `ENVIRONMENT`: staging or production (default: production)
- `--fix`: Auto-fix RuboCop offenses

**Exit Codes**:
- `0`: Ready to deploy
- `1`: Caution required
- `2`: Not ready to deploy
