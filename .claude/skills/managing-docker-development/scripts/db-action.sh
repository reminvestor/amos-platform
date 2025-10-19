#!/bin/bash
# Database operations via Docker Compose

set -e

DB_ACTION="${1:-migrate}"

echo "🗄️  Running database operation: $DB_ACTION"

case "$DB_ACTION" in
  migrate)
    docker-compose exec web rails db:migrate
    ;;

  rollback)
    docker-compose exec web rails db:rollback
    ;;

  seed)
    docker-compose exec web rails db:seed
    ;;

  reset)
    echo "⚠️  This will DROP and recreate the database!"
    docker-compose exec web rails db:reset
    ;;

  drop)
    echo "⚠️  This will DELETE all data. Type 'yes' to confirm:"
    read -r confirm
    if [ "$confirm" = "yes" ]; then
      docker-compose exec web rails db:drop db:create db:migrate db:seed
      echo "✅ Database recreated"
    else
      echo "Cancelled."
      exit 1
    fi
    ;;

  *)
    echo "❌ Unknown db action: $DB_ACTION"
    echo "Available: migrate, rollback, seed, reset, drop"
    exit 1
    ;;
esac
