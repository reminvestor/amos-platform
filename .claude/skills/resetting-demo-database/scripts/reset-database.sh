#!/bin/bash
set -e

# Resetting Demo Database - Safe database reset with seed data
# Usage: reset-database.sh [--skip-confirm] [--seed-file PATH]
# Examples:
#   reset-database.sh                              # Interactive with confirmation
#   reset-database.sh --skip-confirm               # No confirmation (for automation)
#   reset-database.sh --seed-file db/seeds/custom.rb

SKIP_CONFIRM=false
SEED_FILE="db/seeds.rb"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-confirm)
      SKIP_CONFIRM=true
      shift
      ;;
    --seed-file)
      SEED_FILE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: reset-database.sh [--skip-confirm] [--seed-file PATH]"
      exit 1
      ;;
  esac
done

# Confirmation unless skipped
if [ "$SKIP_CONFIRM" = false ]; then
  echo "⚠️  Database Reset to Demo State"
  echo ""
  echo "This will:"
  echo "  1. Drop the current database"
  echo "  2. Create a fresh database"
  echo "  3. Run all migrations"
  echo "  4. Load demo seed data"
  echo ""
  echo "❌ ALL CURRENT DATA WILL BE LOST!"
  echo ""
  read -p "Continue? (yes/no): " CONFIRM

  if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Reset cancelled"
    exit 1
  fi
  echo ""
fi

# Create safety snapshot
echo "📸 Creating safety snapshot before reset..."
echo ""

SNAPSHOT_DIR=".db_snapshots"
mkdir -p "$SNAPSHOT_DIR"

SNAPSHOT_NAME="pre_reset_$(date +%Y%m%d_%H%M%S)"
SNAPSHOT_FILE="$SNAPSHOT_DIR/${SNAPSHOT_NAME}.sql"

# Get database name
DB_NAME=$(docker-compose run --rm web rails runner "puts ActiveRecord::Base.connection_db_config.database" 2>/dev/null | tail -1)

# Create snapshot (ignore errors if DB is empty)
docker-compose exec -T db pg_dump -U postgres "$DB_NAME" > "$SNAPSHOT_FILE" 2>/dev/null || true

if [ -f "$SNAPSHOT_FILE" ] && [ -s "$SNAPSHOT_FILE" ]; then
  SIZE=$(du -h "$SNAPSHOT_FILE" | cut -f1)
  echo "✅ Safety snapshot created: $SNAPSHOT_NAME ($SIZE)"
  echo "   Restore with: ./.claude/skills/managing-database-snapshots/scripts/db-snapshot.sh restore $SNAPSHOT_NAME"
else
  echo "⚠️  Could not create safety snapshot (database may be empty)"
  rm -f "$SNAPSHOT_FILE"
fi

echo ""

# Reset database
echo "🔄 Resetting database..."
echo ""

echo "1️⃣ Dropping database..."
docker-compose run --rm web rails db:drop

echo ""
echo "2️⃣ Creating database..."
docker-compose run --rm web rails db:create

echo ""
echo "3️⃣ Running migrations..."
docker-compose run --rm web rails db:migrate

echo ""
echo "✅ Database structure ready"
echo ""

# Load seed data
if [ ! -f "$SEED_FILE" ]; then
  echo "❌ Seed file not found: $SEED_FILE"
  exit 1
fi

echo "4️⃣ Loading seed data from: $SEED_FILE"
echo ""

if [ "$SEED_FILE" = "db/seeds.rb" ]; then
  # Standard seed file
  docker-compose run --rm web rails db:seed
else
  # Custom seed file
  docker-compose run --rm web rails runner "load '$SEED_FILE'"
fi

echo ""
echo "✅ Seed data loaded"
echo ""

# Verify data
echo "5️⃣ Verifying data..."
echo ""

echo "Record counts:"
docker-compose run --rm web rails runner "
  puts '  Entities: ' + Entity.count.to_s if defined?(Entity)
  puts '  Users: ' + User.count.to_s if defined?(User)
  puts '  Campaigns: ' + Campaign.count.to_s if defined?(Campaign)
  puts '  Contacts: ' + Contact.count.to_s if defined?(Contact)
  puts '  Landing Pages: ' + LandingPage.count.to_s if defined?(LandingPage)
  puts '  Integrations: ' + Integration.count.to_s if defined?(Integration)
" 2>/dev/null | grep -E "^\s+\w+:" || echo "  (Unable to verify - models may not be loaded)"

echo ""
echo "✅ Database verification complete"
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Database Reset Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Your database is now in demo state."
echo ""
echo "Next steps:"
echo "  - Start the app: ./.claude/skills/managing-docker-development/scripts/docker-action.sh start"
echo "  - Access the app: http://app.localhost:3000"
echo "  - Check demo users in $SEED_FILE for login credentials"
echo ""

if [ -f "$SNAPSHOT_FILE" ]; then
  echo "To restore previous data:"
  echo "  ./.claude/skills/managing-database-snapshots/scripts/db-snapshot.sh restore $SNAPSHOT_NAME"
  echo ""
fi
