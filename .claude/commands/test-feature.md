# /test-feature Command

Write comprehensive system tests for a workflow or feature.

## Usage

```
/test-feature [description]
```

## What This Command Does

Delegates to the **rails-system-test-specialist** agent to:
1. Ask about happy path and edge cases
2. Write system tests using Playwright
3. Test end-to-end workflow execution
4. Verify database state changes
5. Run tests and fix failures

## Example

```
/test-feature Test the landing page generation workflow
```

## Agent Task

Use the Task tool with subagent_type: "rails-system-test-specialist"
