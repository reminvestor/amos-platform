# Resetting Demo Database

**Reset database to demo state with seed data**

Safely resets the development database by dropping, recreating, migrating, and loading demo seed data. Creates automatic safety snapshots before reset.

## When to Use

- Starting fresh with demo data for testing
- Recovering from corrupted development database
- Resetting to known-good state after experiments
- Loading custom seed scenarios

## Usage

```bash
# Reset with confirmation prompt (safe, creates snapshot)
./.claude/skills/resetting-demo-database/scripts/reset-database.sh

# Reset without confirmation (for scripts)
./.claude/skills/resetting-demo-database/scripts/reset-database.sh --skip-confirm

# Reset with custom seed file
./.claude/skills/resetting-demo-database/scripts/reset-database.sh --seed-file db/seeds/custom.rb
```

## How It Works

1. **Safety Snapshot**: Creates timestamped .sql backup before any changes
2. **Drop Database**: Removes current database and all data
3. **Create Database**: Creates fresh empty database
4. **Run Migrations**: Applies all schema migrations
5. **Load Seeds**: Runs seed file to populate demo data
6. **Verification**: Counts records in key tables to confirm success

## Safety Features

- **Automatic Snapshots**: Every reset creates a `.db_snapshots/pre_reset_YYYYMMDD_HHMMSS.sql` backup
- **Confirmation Prompt**: Requires explicit "yes" unless `--skip-confirm` flag used
- **Verification**: Validates data loaded successfully after seeding
- **Restore Instructions**: Shows how to restore snapshot if needed

## Examples

**Scenario 1: Standard demo reset**
```bash
$ ./.claude/skills/resetting-demo-database/scripts/reset-database.sh
⚠️  Database Reset to Demo State

This will:
  1. Drop the current database
  2. Create a fresh database
  3. Run all migrations
  4. Load demo seed data

❌ ALL CURRENT DATA WILL BE LOST!

Continue? (yes/no): yes

📸 Creating safety snapshot...
✅ Safety snapshot created: pre_reset_20251017_143022 (2.3M)

🔄 Resetting database...
✅ Database reset complete!

Record counts:
  Entities: 2
  Users: 5
  Campaigns: 3
  Landing Pages: 2
```

**Scenario 2: Custom seed data**
```bash
$ ./.claude/skills/resetting-demo-database/scripts/reset-database.sh --seed-file db/seeds/affiliate_demo.rb
# Loads custom affiliate program demo data instead of standard seeds
```

**Scenario 3: Automated reset (no prompt)**
```bash
$ ./.claude/skills/resetting-demo-database/scripts/reset-database.sh --skip-confirm
# Useful in scripts or CI pipelines
```

## Restoring from Snapshot

If you need to undo the reset:

```bash
# List available snapshots
./.claude/skills/managing-database-snapshots/scripts/db-snapshot.sh list

# Restore a snapshot
./.claude/skills/managing-database-snapshots/scripts/db-snapshot.sh restore pre_reset_20251017_143022
```

## Script Reference

### `reset-database.sh [--skip-confirm] [--seed-file PATH]`

**Options**:
- `--skip-confirm`: Skip confirmation prompt (use in automation)
- `--seed-file PATH`: Custom seed file (default: `db/seeds.rb`)

**Exit Codes**:
- `0`: Reset completed successfully
- `1`: User cancelled at confirmation
- `1`: Seed file not found
- `1`: Database operation failed

## Related Skills

- [Managing Database Snapshots](../managing-database-snapshots/SKILL.md) - Create/restore database backups
- [Managing Docker Development](../managing-docker-development/SKILL.md) - Database migration and operations
