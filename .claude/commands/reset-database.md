# Reset Database

Reset the demo database to initial state.

## Description

Completely resets your development database to a clean state with fresh migrations and optional seed data. Use this when:
- Database becomes corrupted
- Migrations failed partway
- Need a fresh start for testing
- Cleaning up after experiments

## ⚠️ Warning

This command **destructively deletes all data** in your development database. All entities, users, contacts, campaigns, and other data will be lost.

## When to Use

- Starting fresh with demo data
- Cleaning up after integration testing
- Recovering from failed migrations
- Preparing for performance testing

## What It Does

1. Drops the entire database
2. Creates fresh database
3. Runs all migrations
4. Optionally seeds sample data
5. Verifies database integrity

## Usage

```bash
.claude/skills/resetting-demo-database/scripts/reset-database.sh
```

You'll be prompted to confirm before proceeding.

## After Reset

- Fresh database with no data
- All migrations applied
- Ready for new development/testing
