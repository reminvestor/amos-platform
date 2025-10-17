# Quick Guide: Running Affiliate Tests

## Prerequisites

Ensure your test database is set up:

```bash
rails db:test:prepare
```

## Run All Affiliate Tests

```bash
# Run all tests at once
rails test test/models/affiliate*.rb \
           test/models/referral_test.rb \
           test/models/commission_test.rb \
           test/models/payout_test.rb \
           test/services/affiliate*.rb \
           test/services/payout_batch_service_test.rb \
           test/controllers/affiliate/ \
           test/controllers/admin/affiliates_controller_test.rb \
           test/controllers/admin/commissions_controller_test.rb \
           test/controllers/admin/payouts_controller_test.rb \
           test/integration/affiliate_tracking_flow_test.rb \
           test/integration/commission_creation_flow_test.rb \
           test/integration/payout_flow_test.rb
```

## Run by Category

### Model Tests Only
```bash
rails test test/models/affiliate_test.rb \
           test/models/affiliate_click_test.rb \
           test/models/affiliate_tier_test.rb \
           test/models/referral_test.rb \
           test/models/commission_test.rb \
           test/models/payout_test.rb
```

### Service Tests Only
```bash
rails test test/services/affiliate_stats_service_test.rb \
           test/services/affiliate_referral_service_test.rb \
           test/services/affiliate_commission_service_test.rb \
           test/services/payout_batch_service_test.rb
```

### Controller Tests Only
```bash
# Affiliate controllers
rails test test/controllers/affiliate/

# Admin controllers
rails test test/controllers/admin/affiliates_controller_test.rb \
           test/controllers/admin/commissions_controller_test.rb \
           test/controllers/admin/payouts_controller_test.rb
```

### Integration Tests Only
```bash
rails test test/integration/affiliate_tracking_flow_test.rb \
           test/integration/commission_creation_flow_test.rb \
           test/integration/payout_flow_test.rb
```

## Run Individual Test Files

```bash
# Specific model
rails test test/models/affiliate_test.rb

# Specific service
rails test test/services/affiliate_commission_service_test.rb

# Specific controller
rails test test/controllers/affiliate/dashboard_controller_test.rb

# Specific integration test
rails test test/integration/commission_creation_flow_test.rb
```

## Run Specific Test Cases

```bash
# Run a single test by name
rails test test/models/affiliate_test.rb -n test_affiliate_code_should_be_unique

# Run tests matching a pattern
rails test test/models/affiliate_test.rb -n /conversion/
```

## With Coverage

```bash
# Install simplecov (if not already)
# Add to Gemfile: gem 'simplecov', require: false, group: :test

# Run with coverage
COVERAGE=true rails test test/models/affiliate_test.rb
```

## Verbose Output

```bash
# See detailed output
rails test test/models/affiliate_test.rb -v
```

## Parallel Testing

```bash
# Run tests in parallel (Rails 8 default)
rails test
```

## Common Issues & Fixes

### Admin Controller Tests Skipped

The admin controller tests are currently skipped because admin authentication needs to be configured. To enable them:

1. Remove the `skip "Admin authentication needs to be configured"` line
2. Add proper admin authentication setup (e.g., sign_in @admin)

### Database Not Found

```bash
rails db:create db:migrate RAILS_ENV=test
rails db:test:prepare
```

### Fixtures Not Loading

```bash
rails db:fixtures:load RAILS_ENV=test
```

### Missing Dependencies

```bash
bundle install
```

## Test Output Interpretation

```
Running 48 tests in parallel...

Finished in 2.5s
48 runs, 120 assertions, 0 failures, 0 errors, 0 skips
```

- **runs**: Number of test cases executed
- **assertions**: Total assertions across all tests
- **failures**: Tests that failed (assertions returned false)
- **errors**: Tests that raised exceptions
- **skips**: Tests marked with `skip`

## Quick Debugging

### Run with backtrace
```bash
rails test test/models/affiliate_test.rb -b
```

### Run with warnings
```bash
rails test test/models/affiliate_test.rb -w
```

### Run seed (for debugging flaky tests)
```bash
rails test test/models/affiliate_test.rb --seed 12345
```

## Expected Test Count

| Category | Files | Tests |
|----------|-------|-------|
| Models | 6 | 143 |
| Services | 4 | 112 |
| Controllers | 7 | 50 |
| Integration | 3 | 33 |
| **TOTAL** | **20** | **338** |

Note: Admin controller tests (24) are currently skipped, so you'll see fewer runs initially.

## Continuous Integration

Add to your CI pipeline:

```yaml
# .github/workflows/test.yml
- name: Run Affiliate Tests
  run: |
    rails db:test:prepare
    rails test test/models/affiliate*.rb \
               test/models/referral_test.rb \
               test/models/commission_test.rb \
               test/models/payout_test.rb \
               test/services/affiliate*.rb \
               test/services/payout_batch_service_test.rb \
               test/integration/affiliate*.rb \
               test/integration/commission_creation_flow_test.rb \
               test/integration/payout_flow_test.rb
```

## Next Steps

After tests pass:
1. Review coverage report
2. Enable admin controller tests
3. Add additional edge cases as needed
4. Set up CI/CD pipeline
5. Monitor test performance over time
