# Database Snapshot

Create and manage database snapshots for backup and testing.

## Description

Create database snapshots for:
- Backup before risky operations
- Testing with consistent data
- Performance analysis
- Comparing database states
- Recovery from failures
- Sharing test data

## Snapshot Operations

**Create Snapshot**
- Current database state to file
- Compressed backup
- Timestamped archive
- Includes schema and data

**Restore Snapshot**
- Restore from saved snapshot
- Automatic backup of current state
- Data integrity verification
- Confirmation before restore

**List Snapshots**
- View all available snapshots
- File size and date
- Database state info
- Time since snapshot

**Clean Old Snapshots**
- Remove snapshots older than N days
- Save disk space
- Keep recent snapshots

## When to Use

- Before major data migrations
- Before testing destructive operations
- Comparing database states
- Sharing test data with team
- Performance testing with real data
- Disaster recovery

## Usage

```bash
.claude/skills/managing-database-snapshots/scripts/db-snapshot.sh
```

Interactive menu with options:
1. Create snapshot
2. Restore snapshot
3. List snapshots
4. Delete snapshot
5. Compare snapshots

## Storage

Snapshots saved to:
```
db/snapshots/snapshot-{timestamp}.sql.gz
```

## Safety

- Automatic backups before restore
- Verification after restore
- Rollback available
- No automatic cleanup
