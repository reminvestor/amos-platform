# Branch Protection Setup

## GitHub Repository Settings

Go to: **Settings → Branches → Add branch protection rule**

### For `main` branch:

| Setting | Value |
|---------|-------|
| **Require pull request before merging** | ✅ Enabled |
| **Required approvals** | 1 (or 2 for high security) |
| **Dismiss stale PR approvals** | ✅ Enabled |
| **Require review from code owners** | ✅ Enabled |
| **Require status checks to pass** | ✅ Enabled |
| **Require branches to be up to date** | ✅ Enabled |
| **Required checks** | `test`, `lint`, `security` |
| **Require conversation resolution** | ✅ Enabled |
| **Require signed commits** | Optional (recommended) |
| **Include administrators** | ✅ Enabled (even admins need PRs) |
| **Allow force pushes** | ❌ Disabled |
| **Allow deletions** | ❌ Disabled |

### For `prod` branch:

Same as `main`, plus:
- **Restrict who can push** → Only deploy bot/CI
- **Require deployments to succeed** → Staging must pass first

### For `dev` branch:

Lighter rules:
- **Require pull request** → ✅
- **Required approvals** → 1
- **Status checks** → `test`

---

## CODEOWNERS File

Create `.github/CODEOWNERS`:

```
# Default owners for everything
* @amos-labs/maintainers

# Solana programs require extra review
/solana/ @amos-labs/core @amos-labs/security

# Token economy changes require founder approval
/app/services/token_economy_service.rb @rickbarkley
/app/services/contribution_reward_calculator.rb @rickbarkley

# Security-sensitive areas
/app/services/solana_* @amos-labs/security
/config/initializers/security* @amos-labs/security
```

---

## What This Prevents

| Attack | Prevention |
|--------|------------|
| Random user pushes to main | ❌ Blocked - PR required |
| Maintainer skips review | ❌ Blocked - Can't self-approve |
| Force push to rewrite history | ❌ Blocked - Force push disabled |
| Merge failing code | ❌ Blocked - CI must pass |
| Delete branch | ❌ Blocked - Deletion disabled |

---

## CI/CD Workflow

```yaml
# .github/workflows/protect.yml
name: Branch Protection Checks

on:
  pull_request:
    branches: [main, prod, dev]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run tests
        run: bundle exec rails test

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run linter
        run: bundle exec rubocop

  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Security scan
        run: bundle exec brakeman
```

---

## Token Award Flow

```
1. Contributor opens PR against `dev`
2. CI runs → Tests pass
3. AMOS bot analyzes PR:
   - Evaluates complexity
   - Suggests point value
   - Posts comment with estimate
4. Maintainer reviews:
   - Code quality
   - Point estimate
   - Approves or requests changes
5. Merge to `dev`
6. Points credited to contributor's account
7. Later: `dev` → `main` → `prod` promotion
```
