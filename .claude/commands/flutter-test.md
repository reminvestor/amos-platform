---
description: Run Flutter tests with various options
arguments:
  - name: scope
    description: What tests to run (all, unit, integration, file, coverage)
    default: all
  - name: path
    description: Specific test file or directory path (optional)
---

# Run Tests Command

Run Flutter tests based on the specified scope.

## Instructions

Based on the scope argument "$ARGUMENTS.scope", run the appropriate tests:

### Scope: all (default)
Run all unit tests:
```bash
cd flutter_mobile && flutter test
```

### Scope: unit
Run only unit tests (exclude integration tests):
```bash
cd flutter_mobile && flutter test test/
```

### Scope: integration
Run integration tests on the connected device:
```bash
cd flutter_mobile && flutter test integration_test/
```

### Scope: file
Run a specific test file. Use the path argument:
```bash
cd flutter_mobile && flutter test $ARGUMENTS.path
```

### Scope: coverage
Run tests with coverage and generate report:
```bash
cd flutter_mobile && flutter test --coverage && genhtml coverage/lcov.info -o coverage/html
```
Then report the coverage summary.

### Scope: failed
Re-run only previously failed tests:
```bash
cd flutter_mobile && flutter test --run-skipped
```

## After Running Tests

1. Report the total number of tests run
2. Report passed/failed counts
3. If there are failures, list the failing test names
4. For coverage scope, report the coverage percentage

## Examples

- `/flutter-test` - Run all tests
- `/flutter-test unit` - Run unit tests only
- `/flutter-test integration` - Run integration tests
- `/flutter-test file test/services/payout_service_test.dart` - Run specific file
- `/flutter-test coverage` - Run with coverage report
