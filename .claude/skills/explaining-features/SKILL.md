# Explaining Features

**Generate user-facing feature documentation from code**

Automatically creates documentation by analyzing Rails models, controllers, and associations. Supports user, admin, and developer audiences.

## When to Use

- Documenting new features for users
- Creating admin guides for complex features
- Generating developer reference docs
- Onboarding new team members

## Usage

```bash
# Interactive feature selection
./.claude/skills/explaining-features/scripts/explain-feature.sh

# Generate user docs for campaigns
./.claude/skills/explaining-features/scripts/explain-feature.sh campaigns users

# Generate admin docs
./.claude/skills/explaining-features/scripts/explain-feature.sh integrations admins

# Generate developer docs
./.claude/skills/explaining-features/scripts/explain-feature.sh landing_pages developers
```

## Documentation Types

### Users
- What is it?
- How to use (step-by-step)
- Best practices
- FAQ/Help

### Admins
- Technical overview
- Database schema
- Entity scoping details
- Monitoring guidance

### Developers
- Model definition with associations
- Database schema
- Usage examples (CRUD operations)
- Routes

## How It Works

1. **Analyze Feature**: Uses Rails runner to introspect model, columns, associations
2. **Find Controller**: Detects available actions
3. **Generate Docs**: Creates formatted documentation based on audience
4. **Save File**: Writes to `docs/features/{feature}_{audience}.md`

## Script Reference

### `explain-feature.sh [FEATURE] [AUDIENCE]`

**Parameters**:
- `FEATURE`: Feature name (e.g., campaigns, contacts, affiliates)
- `AUDIENCE`: users, admins, or developers (default: users)

**Exit Codes**:
- `0`: Documentation generated successfully
- `1`: Feature not found
