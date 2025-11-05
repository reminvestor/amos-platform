# Quick Start Guide - Test Coverage Skill

Fast reference for using the test coverage skill effectively.

## Quick Commands

### 1. Find All Coverage Gaps
```bash
bash .claude/skills/checking-test-coverage/scripts/detect-gaps.sh
```

**What it does:**
- Scans all models, controllers, services, jobs, mailers
- Finds files without corresponding test files
- Prioritizes gaps (HIGH/MEDIUM/LOW)
- Lists existing e2e tests

**Example Output:**
```
⚠️  Found 59 files without tests

HIGH PRIORITY (22 files):
  app/models/landing_page_dsl.rb (510 lines)
  app/models/connection.rb (126 lines)

MEDIUM PRIORITY (20 files):
  app/models/admin_user.rb (66 lines)
```

---

### 2. Get Recommendations for Specific File
```bash
bash .claude/skills/checking-test-coverage/scripts/recommend-tests.sh <file_path>
```

**What it does:**
- Analyzes code structure (validations, associations, methods)
- Suggests specific tests to write
- Provides test template skeleton

**Examples:**
```bash
# Model
recommend-tests.sh app/models/campaign.rb

# Controller
recommend-tests.sh app/controllers/campaigns_controller.rb

# Service
recommend-tests.sh app/services/bedrock_service.rb

# Job
recommend-tests.sh app/jobs/process_campaign_job.rb
```

**Example Output:**
```
✓ Validations:
  validates :name, presence: true

✓ Associations:
  belongs_to :entity
  has_many :campaigns

✓ Instance Methods (9 found):
  def active?
  def calculate_total

Suggested test structure:
  [Complete test template provided]
```

---

### 3. Get E2E Test Recommendations
```bash
bash .claude/skills/checking-test-coverage/scripts/recommend-tests.sh
```
(No file specified = E2E recommendations)

**What it does:**
- Lists critical user flows to test
- Provides complete system test examples
- Suggests multi-step workflow tests

---

### 4. Run Tests with Coverage
```bash
bash .claude/skills/checking-test-coverage/scripts/analyze-coverage.sh
```

**What it does:**
- Sets up SimpleCov if not already configured
- Runs complete test suite
- Generates coverage report in `coverage/index.html`
- Shows coverage percentages by category

**Options:**
```bash
# Specific category
analyze-coverage.sh --category models
analyze-coverage.sh --category services

# Custom threshold
analyze-coverage.sh --threshold 90
```

---

### 5. Fix Broken Tests
```bash
bash .claude/skills/checking-test-coverage/scripts/fix-tests.sh
```

**What it does:**
- Runs test suite to detect failures
- Analyzes failure patterns
- Attempts automatic fixes
- Re-runs tests to verify fixes

**Common fixes:**
- Missing Devise test helpers
- Authentication setup
- Fixture issues
- Deprecated syntax

---

## Typical Workflows

### Workflow 1: Starting a New Feature
```bash
# 1. Check existing coverage
detect-gaps.sh

# 2. Write code for new feature
# (your implementation)

# 3. Get test recommendations
recommend-tests.sh app/models/new_feature.rb

# 4. Write tests based on recommendations

# 5. Run tests with coverage
analyze-coverage.sh --category models
```

---

### Workflow 2: Improving Coverage Before Release
```bash
# 1. Find high-priority gaps
detect-gaps.sh | grep "HIGH PRIORITY"

# 2. For each high-priority file:
recommend-tests.sh app/models/important_model.rb

# 3. Write tests

# 4. Verify coverage improved
analyze-coverage.sh

# 5. Fix any broken tests
fix-tests.sh
```

---

### Workflow 3: Fixing Failing Tests
```bash
# 1. Run fix script
fix-tests.sh

# 2. Review recommendations

# 3. Apply suggested fixes

# 4. Re-run specific tests
docker-compose run --rm web rails test test/models/model_test.rb

# 5. Verify all pass
docker-compose run --rm web rails test
```

---

## Priority Recommendations

### HIGH Priority Files (Do First)
- Files > 100 lines
- Services and processors
- Controllers with many actions
- Integration-related models

### MEDIUM Priority Files (Do Second)
- Files 50-100 lines
- Jobs and mailers
- Helper services
- Admin controllers

### LOW Priority Files (Do Last)
- Files < 50 lines
- Simple helpers
- Utilities

---

## Coverage Goals

**Minimum Targets:**
- Models: 90%+
- Services: 85%+
- Controllers: 75%+
- Jobs: 80%+
- Overall: 80%+

**E2E Coverage:**
- All critical user flows
- Authentication flows
- Payment/subscription flows
- Multi-step workflows
- File upload/processing
- Error scenarios

---

## Tips & Tricks

### Tip 1: Focus on Business Logic
Prioritize testing:
- Complex calculations
- State transitions
- Validation logic
- Integration points

### Tip 2: Use Test Templates
The skill provides templates in `resources/test-templates.md`:
- Copy template for your file type
- Fill in specifics from recommendations
- Add edge cases

### Tip 3: Test Data Setup
Always use:
- Fixtures for stable data
- `SecureRandom` for unique values
- Entity-scoped test data
- Proper cleanup in teardown

### Tip 4: Mock External Dependencies
For services calling external APIs:
- Use mocha/minitest mocks
- Test both success and failure cases
- Verify retry logic

### Tip 5: Incremental Improvement
Don't try to reach 100% at once:
1. Get high-priority files to 80%
2. Add critical e2e tests
3. Incrementally improve medium-priority
4. Maintain coverage with new features

---

## Troubleshooting

### "SimpleCov not found"
The analyze-coverage script will auto-install it. Just run:
```bash
analyze-coverage.sh
```

### "No coverage data generated"
Make sure you're running tests through the script:
```bash
COVERAGE=true rails test
```

### "Tests failing with authentication errors"
Use the fix-tests script:
```bash
fix-tests.sh
```

Or manually add to test file:
```ruby
include Devise::Test::IntegrationHelpers
sign_in @user
```

### "Coverage report not opening"
Manually open:
```bash
open coverage/index.html
# or
xdg-open coverage/index.html  # Linux
```

---

## Example Session

```bash
# Morning: Check coverage status
$ detect-gaps.sh
⚠️  Found 59 files without tests
HIGH PRIORITY (22 files)

# Pick top priority file
$ recommend-tests.sh app/models/landing_page_dsl.rb
✓ Found 15 methods to test
[Shows detailed recommendations]

# Write tests using template
$ vim test/models/landing_page_dsl_test.rb
# [Write tests based on recommendations]

# Run tests to verify
$ docker-compose run --rm web rails test test/models/landing_page_dsl_test.rb
✓ All tests passing

# Check coverage improved
$ analyze-coverage.sh --category models
Models: 85.6% → 87.2% ✓

# Repeat for next file
```

---

## Integration with Development Workflow

### Pre-commit Hook
Add to `.git/hooks/pre-commit`:
```bash
#!/bin/bash
# Run tests before commit
docker-compose run --rm web rails test
```

### CI/CD Pipeline
```yaml
test:
  script:
    - rails test
    - COVERAGE=true rails test
    - coverage must be > 80%
```

### Weekly Review
Every sprint:
1. Run `detect-gaps.sh`
2. Add top 3 missing tests
3. Review e2e coverage
4. Update test documentation

---

## Resources

- **SKILL.md** - Full skill documentation
- **test-templates.md** - Copy-paste test templates
- **Coverage report** - `coverage/index.html` after running tests

---

**Remember:** Good tests make refactoring safe and bugs rare! 🧪✨
