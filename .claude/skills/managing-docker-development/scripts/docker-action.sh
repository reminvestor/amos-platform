#!/bin/bash
# Execute Docker Compose actions for AMOS development

set -e

ACTION="${1:-start}"
SERVICE="${2:-all}"
SUB_ACTION="${3:-}"

case "$ACTION" in
  start)
    echo "🚀 Starting AMOS development environment..."
    docker-compose up -d
    echo "⏳ Waiting for services..."
    sleep 5
    docker-compose ps
    echo ""
    echo "✅ Services started!"
    echo "📍 Rails app: http://localhost:3000"
    echo "📍 Database: localhost:5432"
    echo "📍 Redis: localhost:6379"
    ;;

  stop)
    echo "🛑 Stopping all services..."
    docker-compose down
    echo "✅ All services stopped"
    ;;

  restart)
    echo "🔄 Restarting services..."
    if [ "$SERVICE" = "all" ]; then
      docker-compose restart
    else
      docker-compose restart "$SERVICE"
    fi
    echo "✅ Services restarted"
    ;;

  rebuild)
    echo "🔨 Rebuilding and restarting..."
    docker-compose down
    if [ "$SERVICE" = "all" ]; then
      docker-compose build --no-cache
    else
      docker-compose build --no-cache "$SERVICE"
    fi
    docker-compose up -d
    echo "✅ Rebuild complete!"
    ;;

  logs)
    echo "📋 Viewing logs..."
    if [ "$SERVICE" = "all" ]; then
      docker-compose logs -f --tail=100
    else
      docker-compose logs -f --tail=100 "$SERVICE"
    fi
    ;;

  console)
    echo "🔧 Opening Rails console..."
    docker-compose exec web rails console
    ;;

  shell)
    echo "🐚 Opening bash shell in web container..."
    docker-compose exec web bash
    ;;

  ps)
    echo "📊 Container status:"
    docker-compose ps
    ;;

  clean)
    echo "🧹 Cleaning up Docker resources..."
    docker-compose down -v
    docker system prune -f
    echo "✅ Cleanup complete!"
    ;;

  *)
    echo "❌ Unknown action: $ACTION"
    echo "Available actions: start, stop, restart, rebuild, logs, console, shell, ps, clean"
    exit 1
    ;;
esac
