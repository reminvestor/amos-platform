# Prepare Dev Environment

Set up complete development environment from scratch.

## Description

Prepares your entire development environment including:
- Docker container setup
- Database initialization
- Redis cache setup
- Gem dependency installation
- Asset compilation
- Environment variables
- Sample data seeding

## Prerequisites

- Git installed
- Docker and Docker Compose installed
- 4GB+ free disk space
- Ruby version manager (rbenv or similar)

## When to Use

- **Fresh developer onboarding** - First time setting up the project
- **New machine setup** - Moving to a different computer
- **After major dependency updates** - Ruby version or gem changes
- **Recovering from corrupted environment** - When services fail
- **Complete reset needed** - Starting fresh (wipes demo data)

**Don't use this if:** You just want to verify your current setup is healthy. Use `/check-deployment` instead.

## What It Does

1. Validates system requirements
2. Configures environment variables
3. Starts Docker services
4. Creates and migrates database
5. Installs Ruby gems
6. Compiles frontend assets
7. Seeds sample data
8. Verifies all components

## Usage

```bash
.claude/skills/preparing-development-environment/scripts/prepare-dev-env.sh
```

## Estimated Time

5-15 minutes depending on system and network speed.

## After Setup

Your development environment will be ready with:
- ✅ Running Rails server (available at http://app.localhost:3000)
- ✅ Active job processor
- ✅ Sample demo entity with test data
- ✅ All services healthy
- ✅ Admin user credentials provided

## Next Steps

1. Sign in at http://app.localhost:3000 with provided credentials
2. Explore Scout AI at /scout
3. To verify health anytime: Use `/check-deployment` command
4. To run tests: Use `/run-tests` command
