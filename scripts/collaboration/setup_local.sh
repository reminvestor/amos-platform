#!/bin/bash
# =============================================================================
# Agent Collaboration System - Local Docker Setup
# =============================================================================
# This script sets up the Agent Collaboration System in the local Docker environment.
# Run this after docker-compose up to initialize energy states and verify the system.
# =============================================================================

set -e

echo "🚀 Agent Collaboration System - Local Setup"
echo "============================================"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker is not running. Please start Docker first.${NC}"
    exit 1
fi

# Check if the web container is running
if ! docker compose ps | grep -q "web.*running"; then
    echo -e "${YELLOW}⚠️  Web container not running. Starting docker-compose...${NC}"
    docker compose up -d
    echo "Waiting for services to be healthy..."
    sleep 30
fi

echo ""
echo "📊 Step 1: Running database migrations..."
docker compose exec web rails db:migrate
echo -e "${GREEN}✅ Migrations complete${NC}"

echo ""
echo "🔋 Step 2: Initializing agent energy states..."
docker compose exec web rails agent_energy:init
echo -e "${GREEN}✅ Energy states initialized${NC}"

echo ""
echo "📈 Step 3: Checking agent energy status..."
docker compose exec web rails agent_energy:status

echo ""
echo "🎓 Step 4: Checking school status..."
docker compose exec web rails agent_energy:school_stats

echo ""
echo "🤝 Step 5: Checking collaboration stats..."
docker compose exec web rails agent_energy:collab_stats

echo ""
echo "============================================"
echo -e "${GREEN}✅ Agent Collaboration System setup complete!${NC}"
echo ""
echo "📍 Access points:"
echo "   - User Dashboard: http://localhost:3000/dashboard/energy"
echo "   - Admin Dashboard: http://localhost:3000/admin/agent_collaboration/dashboard"
echo ""
echo "🛠️  Useful commands:"
echo "   - Regenerate energy: docker compose exec web rails agent_energy:regenerate"
echo "   - Distribute pool:   docker compose exec web rails agent_energy:distribute"
echo "   - Recalibrate:       docker compose exec web rails agent_energy:recalibrate"
echo "   - View status:       docker compose exec web rails agent_energy:status"
echo ""

