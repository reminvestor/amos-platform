# Add Entity

Create test entities with sample data for development.

## Description

This command quickly sets up test entities (tenants) with admin users and optional sample data. It creates entities with contacts, campaigns, landing pages, and other resources. The command handles subdomain generation, user creation with credentials, and provides access URLs.

## When to Use

- Setting up new development environment
- Creating test data for feature development
- Preparing entities for workflow testing
- Demonstrating the application with sample data

## Data Levels

**none** - Entity and admin user only

**minimal** (default) - Basic sample data
- 3 test contacts
- 1 contact group
- 1 email template

**full** - Complete sample data
- All of minimal, plus:
- 7 additional contacts
- Sample campaign
- Sample landing page
- Business profile

## Usage

```bash
.claude/skills/adding-entities-manually/scripts/add-entity.sh
```

You'll be prompted for:
1. Entity name
2. Data level (minimal/full/none)
3. Custom subdomain (optional)

## Output

- Entity ID
- Admin email and password
- Access URL
- Sample data created
