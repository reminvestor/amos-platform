# Managing Database Snapshots

**Save and restore database snapshots for testing and development**

Create timestamped PostgreSQL dumps of your database, restore to previous states, and manage snapshot lifecycle. Essential for testing workflows, preserving data states, and safe experimentation.

## When to Use

- Before risky database migrations or experiments
- Creating known-good states for testing
- Preserving data before resets or schema changes
- Switching between different test scenarios
- Creating backups before major refactors

## Usage

```bash
# Save snapshot with custom name
./.claude/skills/managing-database-snapshots/scripts/db-snapshot.sh save my_snapshot

# Save with auto-generated timestamp name
./.claude/skills/managing-database-snapshots/scripts/db-snapshot.sh save

# List all available snapshots
./.claude/skills/managing-database-snapshots/scripts/db-snapshot.sh list

# Restore from snapshot (with confirmation)
./.claude/skills/managing-database-snapshots/scripts/db-snapshot.sh restore my_snapshot

# Delete snapshot (with confirmation)
./.claude/skills/managing-database-snapshots/scripts/db-snapshot.sh delete my_snapshot
```

## How It Works

**Save**:
1. Creates `.db_snapshots/` directory if not exists
2. Uses `pg_dump` via Docker to export full database
3. Saves as `.sql` file with name or timestamp
4. Shows file size and restore command

**Restore**:
1. Prompts for confirmation (destructive operation)
2. Drops current database
3. Creates fresh database
4. Imports snapshot via `psql`
5. Verifies restoration success

**List**:
- Shows all snapshots with names, sizes, creation dates
- Provides usage examples

**Delete**:
- Prompts for confirmation
- Removes `.sql` file from disk

## Snapshot Storage

All snapshots stored in `.db_snapshots/` directory (gitignored):

```
.db_snapshots/
├── before_migration.sql        # Named snapshot
├── snapshot_20251017_143000.sql # Auto-generated
├── pre_reset_20251017_140530.sql # Created by reset-demo skill
└── working_state.sql            # Named snapshot
```

## Examples

**Scenario 1: Before risky migration**
```bash
$ ./.claude/skills/managing-database-snapshots/scripts/db-snapshot.sh save before_affiliate_migration
📸 Saving database snapshot: before_affiliate_migration

Database: agent_marketing_development
File: .db_snapshots/before_affiliate_migration.sql

✅ Snapshot saved successfully!
   Size: 2.3M
   Location: .db_snapshots/before_affiliate_migration.sql

Restore with: db-snapshot.sh restore before_affiliate_migration
```

**Scenario 2: Restore after failed experiment**
```bash
$ ./.claude/skills/managing-database-snapshots/scripts/db-snapshot.sh restore before_affiliate_migration
⚠️  WARNING: This will replace your current database!

Snapshot: before_affiliate_migration
File: .db_snapshots/before_affiliate_migration.sql

Continue with restore? (yes/no): yes

🔄 Restoring database from snapshot...

1. Dropping existing database...
2. Creating fresh database...
3. Restoring from snapshot...

✅ Database restored successfully!
```

**Scenario 3: Review available snapshots**
```bash
$ ./.claude/skills/managing-database-snapshots/scripts/db-snapshot.sh list
📋 Available database snapshots:

  📸 before_affiliate_migration
     Size: 2.3M
     Created: 2025-10-17 14:30

  📸 pre_reset_20251017_140530
     Size: 1.8M
     Created: 2025-10-17 14:05

  📸 working_state
     Size: 2.1M
     Created: 2025-10-16 16:22
```

**Scenario 4: Clean up old snapshots**
```bash
$ ./.claude/skills/managing-database-snapshots/scripts/db-snapshot.sh delete old_snapshot
🗑️  Delete snapshot:
   Name: old_snapshot
   Size: 1.5M

Confirm deletion? (yes/no): yes
✅ Snapshot deleted: old_snapshot
```

## Best Practices

1. **Name snapshots descriptively**: Use `before_migration`, `working_state`, not generic timestamps
2. **Create before destructive operations**: Always snapshot before drops, resets, or major migrations
3. **Clean up regularly**: Delete old snapshots to save disk space
4. **Verify after restore**: Check record counts to confirm data integrity
5. **Use in testing workflows**: Create snapshots at key test scenario boundaries

## Script Reference

### `db-snapshot.sh ACTION [NAME]`

**Actions**:
- `save [NAME]`: Create snapshot (auto-generates timestamp if no name)
- `restore NAME`: Restore database from snapshot (requires confirmation)
- `list`: Show all available snapshots
- `delete NAME`: Delete snapshot (requires confirmation)

**Parameters**:
- `NAME` (optional for save): Snapshot identifier (excludes `.sql` extension)

**Exit Codes**:
- `0`: Operation completed successfully
- `1`: Operation failed or cancelled by user
- `1`: Snapshot not found (restore/delete)
- `1`: Missing required parameter

## Related Skills

- [Resetting Demo Database](../resetting-demo-database/SKILL.md) - Auto-creates snapshots before reset
- [Managing Docker Development](../managing-docker-development/SKILL.md) - Database operations
