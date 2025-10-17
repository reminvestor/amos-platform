#!/bin/bash
set -e

# Managing Database Snapshots - Save and restore database state
# Usage: db-snapshot.sh ACTION [NAME]
# Actions: save, restore, list, delete
# Examples:
#   db-snapshot.sh save before_migration    # Named snapshot
#   db-snapshot.sh save                     # Auto-generated timestamp
#   db-snapshot.sh list                     # List all snapshots
#   db-snapshot.sh restore before_migration # Restore from snapshot
#   db-snapshot.sh delete old_snapshot      # Delete snapshot

ACTION="${1:-save}"
SNAPSHOT_NAME="$2"
SNAPSHOT_DIR=".db_snapshots"

case "$ACTION" in
  list)
    echo "📋 Available database snapshots:"
    echo ""

    if [ ! -d "$SNAPSHOT_DIR" ]; then
      echo "No snapshots found"
      exit 0
    fi

    if [ -z "$(ls -A $SNAPSHOT_DIR/*.sql 2>/dev/null)" ]; then
      echo "No snapshots found"
    else
      for snapshot in $SNAPSHOT_DIR/*.sql; do
        if [ -f "$snapshot" ]; then
          FILENAME=$(basename "$snapshot" .sql)
          SIZE=$(du -h "$snapshot" | cut -f1)
          # macOS stat format
          MODIFIED=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$snapshot" 2>/dev/null || \
                     stat -c "%y" "$snapshot" 2>/dev/null | cut -d'.' -f1 || \
                     echo "Unknown")

          echo "  📸 $FILENAME"
          echo "     Size: $SIZE"
          echo "     Created: $MODIFIED"
          echo ""
        fi
      done
    fi

    echo "Usage:"
    echo "  Save: db-snapshot.sh save [name]"
    echo "  Restore: db-snapshot.sh restore <name>"
    echo "  Delete: db-snapshot.sh delete <name>"
    ;;

  save)
    mkdir -p "$SNAPSHOT_DIR"

    # Generate snapshot name
    if [ -z "$SNAPSHOT_NAME" ]; then
      SNAPSHOT_NAME="snapshot_$(date +%Y%m%d_%H%M%S)"
    fi

    SNAPSHOT_FILE="$SNAPSHOT_DIR/${SNAPSHOT_NAME}.sql"

    echo "📸 Saving database snapshot: $SNAPSHOT_NAME"
    echo ""

    # Get database name from Rails
    DB_NAME=$(docker-compose run --rm web rails runner "puts ActiveRecord::Base.connection_db_config.database" 2>/dev/null | tail -1)

    echo "Database: $DB_NAME"
    echo "File: $SNAPSHOT_FILE"
    echo ""

    # Create dump using pg_dump via docker
    docker-compose exec -T db pg_dump -U postgres "$DB_NAME" > "$SNAPSHOT_FILE"

    if [ $? -eq 0 ]; then
      SIZE=$(du -h "$SNAPSHOT_FILE" | cut -f1)
      echo "✅ Snapshot saved successfully!"
      echo "   Size: $SIZE"
      echo "   Location: $SNAPSHOT_FILE"
      echo ""
      echo "Restore with:"
      echo "  db-snapshot.sh restore $SNAPSHOT_NAME"
    else
      echo "❌ Failed to create snapshot"
      rm -f "$SNAPSHOT_FILE"
      exit 1
    fi
    ;;

  restore)
    if [ -z "$SNAPSHOT_NAME" ]; then
      echo "❌ Snapshot name required for restore"
      echo ""
      echo "Available snapshots:"
      ls -1 $SNAPSHOT_DIR/*.sql 2>/dev/null | sed 's|.db_snapshots/||' | sed 's|.sql||' | sed 's|^|  - |' || echo "  (none)"
      exit 1
    fi

    SNAPSHOT_FILE="$SNAPSHOT_DIR/${SNAPSHOT_NAME}.sql"

    if [ ! -f "$SNAPSHOT_FILE" ]; then
      echo "❌ Snapshot not found: $SNAPSHOT_NAME"
      echo ""
      echo "Available snapshots:"
      ls -1 $SNAPSHOT_DIR/*.sql 2>/dev/null | sed 's|.db_snapshots/||' | sed 's|.sql||' | sed 's|^|  - |' || echo "  (none)"
      exit 1
    fi

    echo "⚠️  WARNING: This will replace your current database!"
    echo ""
    echo "Snapshot: $SNAPSHOT_NAME"
    echo "File: $SNAPSHOT_FILE"
    echo ""
    read -p "Continue with restore? (yes/no): " CONFIRM

    if [ "$CONFIRM" != "yes" ]; then
      echo "❌ Restore cancelled"
      exit 1
    fi

    echo ""
    echo "🔄 Restoring database from snapshot..."
    echo ""

    # Get database name
    DB_NAME=$(docker-compose run --rm web rails runner "puts ActiveRecord::Base.connection_db_config.database" 2>/dev/null | tail -1)

    echo "1. Dropping existing database..."
    docker-compose run --rm web rails db:drop

    echo "2. Creating fresh database..."
    docker-compose run --rm web rails db:create

    echo "3. Restoring from snapshot..."
    cat "$SNAPSHOT_FILE" | docker-compose exec -T db psql -U postgres "$DB_NAME"

    if [ $? -eq 0 ]; then
      echo ""
      echo "✅ Database restored successfully!"
      echo ""
      echo "Snapshot: $SNAPSHOT_NAME"
    else
      echo ""
      echo "❌ Failed to restore snapshot"
      exit 1
    fi
    ;;

  delete)
    if [ -z "$SNAPSHOT_NAME" ]; then
      echo "❌ Snapshot name required for delete"
      echo ""
      echo "Available snapshots:"
      ls -1 $SNAPSHOT_DIR/*.sql 2>/dev/null | sed 's|.db_snapshots/||' | sed 's|.sql||' | sed 's|^|  - |' || echo "  (none)"
      exit 1
    fi

    SNAPSHOT_FILE="$SNAPSHOT_DIR/${SNAPSHOT_NAME}.sql"

    if [ ! -f "$SNAPSHOT_FILE" ]; then
      echo "❌ Snapshot not found: $SNAPSHOT_NAME"
      exit 1
    fi

    SIZE=$(du -h "$SNAPSHOT_FILE" | cut -f1)

    echo "🗑️  Delete snapshot:"
    echo "   Name: $SNAPSHOT_NAME"
    echo "   Size: $SIZE"
    echo ""
    read -p "Confirm deletion? (yes/no): " CONFIRM

    if [ "$CONFIRM" != "yes" ]; then
      echo "❌ Deletion cancelled"
      exit 1
    fi

    rm "$SNAPSHOT_FILE"
    echo "✅ Snapshot deleted: $SNAPSHOT_NAME"
    ;;

  *)
    echo "❌ Unknown action: $ACTION"
    echo ""
    echo "Usage: db-snapshot.sh ACTION [NAME]"
    echo ""
    echo "Actions:"
    echo "  save [NAME]    - Create snapshot (auto-generates timestamp if no name)"
    echo "  restore NAME   - Restore database from snapshot"
    echo "  list          - Show all available snapshots"
    echo "  delete NAME   - Delete snapshot"
    exit 1
    ;;
esac
