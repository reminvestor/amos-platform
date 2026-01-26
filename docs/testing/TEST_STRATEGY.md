# Test Strategy

> Ensuring quality through comprehensive, fast, and reliable testing

## Overview

Our testing strategy follows a **pyramid approach** with multiple layers:

```
                    ┌───────────────────┐
                    │   System Tests    │  (slowest, few)
                    │   Browser-based   │
                    └─────────┬─────────┘
                              │
                    ┌─────────┴─────────┐
                    │  Integration Tests │  (medium speed)
                    │  Cross-component   │
                    └─────────┬─────────┘
                              │
              ┌───────────────┴───────────────┐
              │          Unit Tests           │  (fastest, many)
              │  Models, Services, Jobs       │
              └───────────────────────────────┘
```

## Test Categories

### 1. Critical Path Tests (Must Pass)

These tests cover core platform functionality and must pass before any deploy:

| Area | Tests | Purpose |
|------|-------|---------|
| Experience Learning | `test/models/task_experience_test.rb`, `test/services/learning/` | Training-Free GRPO implementation |
| Living Platform | `test/services/living_platform/` | Evolution, perception, desire engine |
| Context Graph | `test/services/context_graph/`, `test/models/decision_trace_test.rb` | Decision recording |
| Dynamic Context | `test/services/dynamic_context_service_test.rb` | Amos + Loadouts core |

**Run:** `bin/rails test:critical`

### 2. Unit Tests (Fast Feedback)

Quick tests for individual components:

- **Models:** `test/models/` (50 tests)
- **Services:** `test/services/` (33+ tests)
- **Jobs:** `test/jobs/` (15 tests)

**Run:** `bin/rails test:fast`

### 3. Controller Tests

API and web controller tests:

- **API:** `test/controllers/api/` (30+ tests)
- **Admin:** `test/controllers/admin/` (6 tests)
- **Web:** `test/controllers/` (15 tests)

**Run:** `bin/rails test test/controllers/`

### 4. Integration Tests

End-to-end flows across multiple components:

- `test/integration/experience_learning_flow_test.rb`
- `test/integration/living_platform_integration_test.rb`
- `test/integration/aws_bedrock_pipeline_test.rb`

**Run:** `bin/rails test test/integration/`

### 5. System Tests

Browser-based UI tests (slowest):

- `test/system/`

**Run:** `bin/rails test:system`

## CI/CD Pipeline

### GitHub Actions Workflow

Tests run in parallel for speed:

```yaml
Jobs:
  ├── lint (fast, blocks everything)
  ├── unit_tests_models (parallel)
  ├── unit_tests_services (parallel)
  ├── unit_tests_jobs (parallel)
  ├── controller_tests (parallel)
  ├── critical_path_tests (parallel, must pass)
  ├── integration_tests (after unit tests)
  ├── system_tests (after integration)
  └── deploy_ready (all must pass)
```

### AWS CodePipeline

```
Source → Test Stage → Build Stage → Deploy
            │
            └── Uses buildspec-test.yml
                Runs critical + full test suite
                Blocks deploy if any test fails
```

## Coverage Requirements

| Category | Minimum Coverage | Target |
|----------|-----------------|--------|
| Overall | 60% | 80% |
| Per File | 40% | 60% |
| Critical Paths | 80% | 95% |

### Running with Coverage

```bash
# Full suite with coverage
COVERAGE=true bin/rails test

# Or use rake task
bin/rails test:coverage
```

Coverage report generated in `coverage/index.html`

## Test Commands

| Command | Purpose |
|---------|---------|
| `bin/rails test` | Run all tests |
| `bin/rails test:critical` | Critical path tests only |
| `bin/rails test:fast` | Fast unit tests |
| `bin/rails test:experience_learning` | Experience learning tests |
| `bin/rails test:living_platform` | Living platform tests |
| `bin/rails test:api` | API controller tests |
| `bin/rails test:pre_deploy` | Pre-deploy validation |
| `bin/rails test:coverage` | Full suite with coverage |
| `bin/rails test:stats` | Show test statistics |

## Writing New Tests

### Required Tests for New Features

1. **Model changes:** Add model test
2. **Service changes:** Add service test
3. **API endpoints:** Add controller test
4. **Cross-component flows:** Add integration test
5. **UI changes:** Consider system test

### Test File Structure

```
test/
├── models/                  # ActiveRecord model tests
├── services/
│   ├── living_platform/     # Living platform services
│   ├── learning/            # Experience learning services
│   ├── context_graph/       # Context graph services
│   └── ...
├── controllers/
│   ├── api/v1/              # API controller tests
│   ├── admin/               # Admin controller tests
│   └── ...
├── integration/             # Cross-component flows
├── jobs/                    # Background job tests
└── system/                  # Browser-based tests
```

### Test Fixtures

Located in `test/fixtures/`:

- `entities.yml` - Test entities
- `users.yml` - Test users
- `task_experiences.yml` - Experience learning fixtures
- `decision_traces.yml` - Context graph fixtures

## Pre-Deploy Checklist

Before deploying to production:

- [ ] `bin/rails test:critical` passes
- [ ] `bin/rails test:fast` passes
- [ ] `bin/rails test test/controllers/` passes
- [ ] `bin/rails test:integration` passes
- [ ] No new lint errors (`bin/rubocop`)
- [ ] No security warnings (`bin/brakeman`)

Or simply: `bin/rails test:pre_deploy`

## Troubleshooting

### Tests failing in CI but passing locally

1. Check parallelization issues
2. Verify database state (fixtures)
3. Check environment variables
4. Look for time-dependent tests

### Slow tests

1. Use `bin/rails test:fast` for quick feedback
2. Run specific test files
3. Check for N+1 queries in tests

### Flaky tests

1. Add retry logic for network-dependent tests
2. Use proper waiting for async operations
3. Mock external services
