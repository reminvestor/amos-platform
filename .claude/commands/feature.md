# /feature Command

Start a new feature branch and set up development workflow.

## Usage

```
/feature <feature-name>
```

## What This Command Does

Invokes the **Starting Features** skill to:
- ✅ Create a new feature branch from main/dev
- ✅ Set up development environment
- ✅ Create initial file structure if needed
- ✅ Run database migrations if pending
- ✅ Verify tests pass before starting
- ✅ Set up pre-commit hooks

## Examples

```
# Start new feature
/feature user-authentication

# Start feature from specific branch
/feature payment-integration
```

## Instructions

Use the Skill tool to invoke the `starting-features` skill to create a new feature branch and set up the development workflow. The feature name should be in kebab-case format.
