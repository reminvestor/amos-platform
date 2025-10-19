# Preparing Development Environment

Complete development environment setup in one command.

## Description

This skill chains together multiple common setup tasks to prepare a fully-functional development environment. It handles Docker containers, database setup, test entity creation with sample data, and documentation updates. This is the go-to command when starting fresh, onboarding new developers, or resetting your local environment.

**Use this skill when:**
- Setting up development environment for first time
- Onboarding new developers to the project
- Resetting local environment after major changes
- Preparing for feature development or testing
- After pulling major changes that affect setup

## Instructions

### What This Skill Does

Executes a complete setup workflow:

1. **Health Check** - Verifies application is ready
   - Checks Docker containers are running
   - Validates database connectivity
   - Ensures Rails can boot properly

2. **Database Setup** - Prepares database
   - Runs migrations to latest version
   - Seeds any required data
   - Verifies schema is up to date

3. **Entity Creation** - Creates test entity (optional)
   - Prompts for entity name
   - Creates entity with full sample data
   - Sets up admin user with credentials

4. **Documentation Update** - Syncs docs (optional)
   - Updates tools documentation
   - Updates workflow templates docs
   - Updates models reference

5. **Summary** - Provides access information
   - Shows URLs and credentials
   - Lists available workflows
   - Suggests next steps

### Usage Patterns

**Full Setup (Interactive):**
```
Use preparing-development-environment
```
Prompts for entity name and runs complete setup.

**Quick Setup (No Entity):**
```
Use preparing-development-environment with skip_entity=true
```
Skips entity creation, just ensures app is ready.

**Setup Without Docs:**
```
Use preparing-development-environment with skip_docs=true
```
Skips documentation update step.

**Minimal Setup:**
```
Use preparing-development-environment with skip_entity=true skip_docs=true
```
Only verifies health and database.

### Parameters

- `entity_name` - Name for test entity (optional, prompts if not provided)
- `skip_entity` - Skip entity creation (default: `false`)
- `skip_docs` - Skip documentation updates (default: `false`)

### What You Get

After successful execution:

**Application Ready:**
- Docker containers running
- Database migrated and seeded
- Rails server accessible

**Test Entity (if created):**
- Named entity with subdomain
- Admin user: `admin@{subdomain}.test` / `password123`
- 10 contacts, campaign, landing page, email template
- Business profile configured

**Documentation (if updated):**
- Current tools reference
- Workflow templates guide
- Models schema documentation

**Access Information:**
- Main app URL
- Scout AI chat URL
- Admin credentials
- Quick start commands

## Examples

### New Developer Onboarding

```
Use preparing-development-environment with entity_name='Acme Demo'
```

Output:
```
✅ Environment Setup Complete!

Entity: Acme Demo (ID: 1)
URL: http://acme-demo.localhost:3000
Scout AI: http://acme-demo.localhost:3000/scout

Admin Login:
  Email: admin@acme-demo.test
  Password: password123

Data Created:
  - 10 contacts
  - 1 campaign (draft)
  - 1 landing page
  - 1 email template

Next Steps:
  - Sign in with admin credentials
  - Try: "Create a landing page for our new product"
  - Test workflows: Use testing-workflows
```

### Quick Environment Check

```
Use preparing-development-environment with skip_entity=true skip_docs=true
```

Verifies Docker is running, database is migrated, app is accessible. Minimal overhead for quick checks.

### Reset After Major Changes

```
Use preparing-development-environment with entity_name='Fresh Start'
```

Creates clean environment with new test entity and updated documentation.

## Resources

- [Setup Script](scripts/prepare-dev-env.sh) - Main orchestration script
- [Environment Checklist](resources/environment-checklist.md) - Manual verification steps
