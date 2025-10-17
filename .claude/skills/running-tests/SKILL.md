# Running Tests

A comprehensive test runner for Rails applications with multiple execution modes and smart test selection.

## Description

This skill provides intelligent test execution for Rails projects. It supports running all tests, only affected tests based on git changes, specific test files, watch mode for continuous testing, and coverage reporting. The skill automatically detects the test framework (Rails/Minitest) and provides interactive mode selection.

**Use this skill when:**
- Running the test suite
- Testing specific files or features
- Checking test coverage
- Running tests affected by code changes
- Setting up continuous testing workflow

## Instructions

### Test Execution Modes

1. **All Tests** - Runs the complete test suite
2. **Affected Tests** - Runs only tests impacted by git changes
3. **Specific File** - Runs a single test file
4. **Watch Mode** - Continuously re-runs tests on file changes
5. **Coverage** - Generates test coverage report

### Usage

When invoked, the skill will:
1. Display available test modes
2. Prompt for mode selection (if not specified)
3. Execute the selected test strategy
4. Report results and coverage information

### Mode Selection

The skill accepts mode input in multiple formats:
- Mode name: `all`, `affected`, `file`, `watch`, `coverage`
- Mode number: `1`, `2`, `3`, `4`, `5`
- Legacy letters: `a`, `b`, `c`, `d`, `e` (for backwards compatibility)

### Affected Tests Strategy

The affected tests mode intelligently maps changed files to their corresponding tests:
- `app/models/*.rb` → `test/models/*_test.rb`
- `app/controllers/*.rb` → `test/controllers/*_test.rb`
- `app/services/*.rb` → `test/services/*_test.rb`
- `app/services/tools/*.rb` → `test/services/tools/*_test.rb`

### Running the Tests

All test modes use Docker Compose to ensure consistent environment:

```bash
# Run all tests
docker-compose run --rm web rails test

# Run with coverage
COVERAGE=true docker-compose run --rm web rails test

# Run specific file
docker-compose run --rm web rails test <path>
```

### Coverage Reporting

When coverage is enabled:
- Test coverage is collected using SimpleCov (or configured tool)
- Report is generated in `coverage/index.html`
- Open with: `open coverage/index.html`

### Watch Mode

Watch mode requires `fswatch` for optimal experience:
- Install: `brew install fswatch` (macOS)
- Watches: `app/`, `test/`, `lib/` directories
- Press Ctrl+C to stop

### Test Output

The skill provides clear output formatting:
- 🧪 Test execution progress
- ✅ Success indicators
- ⚠️ Warnings for missing files
- 📊 Coverage statistics
- 🎯 Affected test selection

## Examples

**Interactive mode selection:**
```
Use running-tests skill
```

**Run all tests:**
```
Use running-tests skill with mode=all
```

**Run affected tests only:**
```
Use running-tests skill with mode=affected
```

**Run specific test file:**
```
Use running-tests skill with mode=file path=test/models/campaign_test.rb
```

**Run with coverage:**
```
Use running-tests skill with mode=all coverage=true
```

**Watch mode:**
```
Use running-tests skill with mode=watch
```

## Resources

For implementation details, see:
- [Test Runner Script](resources/test-modes.md) - Detailed mode implementations
- [Affected Tests Logic](resources/affected-tests.md) - File mapping rules
