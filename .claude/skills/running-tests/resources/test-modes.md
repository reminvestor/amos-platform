# Test Modes Reference

## Mode 1: All Tests

Runs the complete test suite using `docker-compose run --rm web rails test`.

**When to use:**
- Before committing major changes
- Running full CI/CD validation
- Checking overall test health

**Options:**
- Set `COVERAGE=true` to generate coverage report

## Mode 2: Affected Tests

Intelligently runs only tests affected by recent code changes.

**File Mapping Logic:**
```
app/models/user.rb → test/models/user_test.rb
app/controllers/campaigns_controller.rb → test/controllers/campaigns_controller_test.rb
app/services/planner_agent_service.rb → test/services/planner_agent_service_test.rb
app/services/tools/create_object_tool.rb → test/services/tools/create_object_tool_test.rb
```

**Change Detection:**
- Compares current branch against `main` branch
- Falls back to `HEAD~1` if main comparison fails
- Skips running if no changes detected

## Mode 3: Specific File

Runs a single test file specified by path.

**Examples:**
```bash
test/models/campaign_test.rb
test/controllers/scout_controller_test.rb
test/services/affiliate_commission_service_test.rb
```

## Mode 4: Watch Mode

Continuously monitors file changes and re-runs tests.

**Requirements:**
- `fswatch` (install via `brew install fswatch` on macOS)
- Alternative: Falls back to 5-second polling

**Watched Directories:**
- `app/`
- `test/`
- `lib/`

**Usage:**
- Press Ctrl+C to stop watching

## Mode 5: Coverage

Runs all tests with coverage reporting enabled.

**Output:**
- Coverage report generated in `coverage/index.html`
- View with `open coverage/index.html`

**Configuration:**
- Uses SimpleCov or configured coverage tool
- Minimum coverage thresholds defined in test helper
