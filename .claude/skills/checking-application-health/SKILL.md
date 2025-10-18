# Checking Application Health

**Comprehensive health check for tests, linting, security, dependencies, and database**

Run automated checks across your application stack to verify everything is working correctly. Detects issues early and provides actionable recommendations.

## When to Use

- Before committing code changes
- Before deploying to production
- After pulling latest code
- Diagnosing mysterious failures
- Verifying development environment setup
- Pre-PR quality gate

## Usage

```bash
# Interactive mode (choose scope)
./.claude/skills/checking-application-health/scripts/health-check.sh

# Full comprehensive check
./.claude/skills/checking-application-health/scripts/health-check.sh all

# Quick check (linting + critical tests)
./.claude/skills/checking-application-health/scripts/health-check.sh quick

# Specific checks
./.claude/skills/checking-application-health/scripts/health-check.sh tests
./.claude/skills/checking-application-health/scripts/health-check.sh lint
./.claude/skills/checking-application-health/scripts/health-check.sh security

# With auto-fix enabled
./.claude/skills/checking-application-health/scripts/health-check.sh all --fix
```

## What Gets Checked

### Full Health Check (`all`)
1. **Database Status**
   - Database container running
   - Pending migrations
   - Schema consistency

2. **Dependencies**
   - Outdated gems
   - Security vulnerabilities (bundler-audit)

3. **Linting (RuboCop)**
   - Style violations
   - Code quality issues
   - Auto-fixable offenses

4. **Test Suite**
   - Full test suite execution
   - Test failures and errors
   - Coverage indicators

5. **Security Scan (Brakeman)**
   - Rails-specific vulnerabilities
   - SQL injection risks
   - XSS vulnerabilities
   - Authentication issues

6. **Code Quality Metrics**
   - File counts
   - Test coverage ratio
   - Code quality indicators

### Quick Health Check (`quick`)
- RuboCop linting
- Critical tests only (models + services)

### Specific Scopes
- `tests`: Test suite only
- `lint`: RuboCop only
- `security`: Security scan only

## How It Works

1. **Initialize Tracking**: Creates issue counter
2. **Run Selected Checks**: Executes each check in sequence
3. **Increment Issues**: Tracks failures across checks
4. **Generate Report**: Provides final status with recommendations
5. **Exit Status**: Returns appropriate code for CI integration

## Health Status Codes

- 🟢 **HEALTHY** (0 issues): All checks passed
- 🟡 **NEEDS ATTENTION** (1-2 issues): Minor issues detected
- 🔴 **UNHEALTHY** (3+ issues): Critical issues require immediate attention

## Examples

**Scenario 1: Full health check**
```bash
$ ./.claude/skills/checking-application-health/scripts/health-check.sh all
🏥 Starting Health Check...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📊 Checking database status...
  ✅ Database is running
  ✅ No pending migrations

📦 Checking dependencies...
  ✅ All gems up to date
  ✅ No known vulnerabilities

🔍 Running RuboCop...
  ✅ No RuboCop offenses

🧪 Running test suite...
  Running full test suite...
  ✅ All tests passing

🔒 Running security scan...
  ✅ No security issues found

📈 Code quality metrics...
  Ruby files: 145
  Test files: 89
  Test coverage ratio: 61.4%
  ✅ Good test coverage

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Health Check Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ All checks passed! Your application is healthy.

Status: 🟢 HEALTHY
```

**Scenario 2: Quick pre-commit check**
```bash
$ ./.claude/skills/checking-application-health/scripts/health-check.sh quick
🏥 Starting Health Check...

🔍 Running RuboCop...
  ❌ RuboCop offenses found
     Run with --fix to auto-correct

🧪 Running test suite...
  Running quick tests (models + services)...
  ✅ All tests passing

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Health Check Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠️  1 issue(s) found - Minor issues detected

Status: 🟡 NEEDS ATTENTION

Recommendations:
  - Review issues above
  - Run with --fix to auto-fix where possible
  - Use specific skills for detailed fixes:
    • fixing-rubocop-offenses - Fix linting issues
```

**Scenario 3: Auto-fix mode**
```bash
$ ./.claude/skills/checking-application-health/scripts/health-check.sh lint --fix
🔍 Running RuboCop...
  ❌ RuboCop offenses found

  🔧 Auto-fixing RuboCop offenses...
  Inspecting 145 files
  ====================

  145 files inspected, 23 offenses corrected
  ✅ Auto-fix complete
```

**Scenario 4: Security scan only**
```bash
$ ./.claude/skills/checking-application-health/scripts/health-check.sh security
🔒 Running security scan...
  ⚠️  Potential security issues detected
     Review with: docker-compose run --rm web bundle exec brakeman

Status: 🟡 NEEDS ATTENTION
```

## Auto-Fix Capabilities

When `--fix` flag is enabled:
- **RuboCop**: Runs with `-a` (auto-correct safe offenses)
- **Other checks**: Provides guidance for manual fixes

## Script Reference

### `health-check.sh [SCOPE] [--fix]`

**Scopes**:
- `all`: Full comprehensive check (default if interactive declined)
- `quick`: Linting + critical tests only
- `tests`: Test suite only
- `lint`: RuboCop linting only
- `security`: Security scan only
- (no argument): Interactive mode, prompts for scope

**Flags**:
- `--fix`: Enable auto-fix for RuboCop offenses

**Exit Codes**:
- `0`: All checks passed (🟢 HEALTHY)
- `1`: 1-2 issues found (🟡 NEEDS ATTENTION)
- `2`: 3+ issues found (🔴 UNHEALTHY)

## Integration with Other Skills

Use health check as part of workflows:

```bash
# Pre-commit workflow
./.claude/skills/fixing-rubocop-offenses/scripts/fix-rubocop.sh
./.claude/skills/checking-application-health/scripts/health-check.sh quick
./.claude/skills/making-quick-commits/scripts/quick-commit.sh

# Pre-deploy workflow
./.claude/skills/checking-application-health/scripts/health-check.sh all
./.claude/skills/running-tests/scripts/run-all-tests.sh
```

## Related Skills

- [Fixing RuboCop Offenses](../fixing-rubocop-offenses/SKILL.md) - Auto-fix linting issues
- [Running Tests](../running-tests/SKILL.md) - Detailed test execution
- [Managing Docker Development](../managing-docker-development/SKILL.md) - Database operations
- [Running Workflows](../running-workflows/SKILL.md) - Pre-commit/pre-deploy workflows

## Resources

- [Troubleshooting Guide](resources/troubleshooting-guide.md) - Comprehensive guide for common issues
