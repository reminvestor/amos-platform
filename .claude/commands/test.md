# /test Command

Run tests for the Rails application.

## Usage

```
/test [path or pattern]
```

## What This Command Does

Invokes the **Running Tests** skill to:
- ✅ Run all tests or specific test files
- ✅ Run tests by pattern (models, controllers, services)
- ✅ Show test results and coverage
- ✅ Debug failing tests
- ✅ Run system tests
- ✅ Run workflow/agent tests

## Examples

```
# Run all tests
/test

# Run specific test file
/test test/models/campaign_test.rb

# Run all model tests
/test test/models

# Run agent system tests
/test test:agents
```

## Instructions

Use the Skill tool to invoke the `running-tests` skill to execute tests based on the user's request. If no path is provided, run the full test suite.
