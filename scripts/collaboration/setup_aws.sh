#!/bin/bash
# =============================================================================
# Agent Collaboration System - AWS Setup (Dev/Prod)
# =============================================================================
# This script sets up the Agent Collaboration System in AWS ECS environments.
# It runs migrations and initializes energy states for all agents.
#
# Usage:
#   ./scripts/collaboration/setup_aws.sh dev
#   ./scripts/collaboration/setup_aws.sh prod
# =============================================================================

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check arguments
if [ -z "$1" ]; then
    echo -e "${RED}❌ Usage: $0 <environment>${NC}"
    echo "   Environments: dev, prod"
    exit 1
fi

ENV=$1

# Validate environment
if [ "$ENV" != "dev" ] && [ "$ENV" != "prod" ]; then
    echo -e "${RED}❌ Invalid environment: $ENV${NC}"
    echo "   Valid environments: dev, prod"
    exit 1
fi

echo "🚀 Agent Collaboration System - AWS $ENV Setup"
echo "================================================"

# Set AWS variables based on environment
if [ "$ENV" == "dev" ]; then
    CLUSTER="agent-marketing-dev"
    SERVICE="agent-marketing-dev-service"
    TASK_FAMILY="agent-marketing-dev"
    AWS_REGION="${AWS_REGION:-us-east-1}"
elif [ "$ENV" == "prod" ]; then
    CLUSTER="agent-marketing-prod"
    SERVICE="agent-marketing-prod-service"
    TASK_FAMILY="agent-marketing-prod"
    AWS_REGION="${AWS_REGION:-us-east-1}"
fi

echo -e "${BLUE}📍 Environment: $ENV${NC}"
echo -e "${BLUE}📍 Cluster: $CLUSTER${NC}"
echo -e "${BLUE}📍 Region: $AWS_REGION${NC}"
echo ""

# Function to run a Rails task in ECS
run_ecs_task() {
    local COMMAND=$1
    local DESCRIPTION=$2
    
    echo -e "${YELLOW}⏳ $DESCRIPTION...${NC}"
    
    # Get the latest task definition
    TASK_DEF=$(aws ecs describe-task-definition \
        --task-definition $TASK_FAMILY \
        --region $AWS_REGION \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text)
    
    # Get network configuration from the service
    NETWORK_CONFIG=$(aws ecs describe-services \
        --cluster $CLUSTER \
        --services $SERVICE \
        --region $AWS_REGION \
        --query 'services[0].networkConfiguration' \
        --output json)
    
    # Run the task
    TASK_ARN=$(aws ecs run-task \
        --cluster $CLUSTER \
        --task-definition $TASK_DEF \
        --network-configuration "$NETWORK_CONFIG" \
        --launch-type FARGATE \
        --overrides "{
            \"containerOverrides\": [{
                \"name\": \"web\",
                \"command\": [\"bash\", \"-c\", \"$COMMAND\"]
            }]
        }" \
        --region $AWS_REGION \
        --query 'tasks[0].taskArn' \
        --output text)
    
    echo -e "${BLUE}   Task ARN: $TASK_ARN${NC}"
    
    # Wait for task to complete
    echo "   Waiting for task to complete..."
    aws ecs wait tasks-stopped \
        --cluster $CLUSTER \
        --tasks $TASK_ARN \
        --region $AWS_REGION
    
    # Check exit code
    EXIT_CODE=$(aws ecs describe-tasks \
        --cluster $CLUSTER \
        --tasks $TASK_ARN \
        --region $AWS_REGION \
        --query 'tasks[0].containers[0].exitCode' \
        --output text)
    
    if [ "$EXIT_CODE" == "0" ]; then
        echo -e "${GREEN}   ✅ $DESCRIPTION complete${NC}"
    else
        echo -e "${RED}   ❌ $DESCRIPTION failed (exit code: $EXIT_CODE)${NC}"
        
        # Get logs
        echo "   Fetching logs..."
        TASK_ID=$(echo $TASK_ARN | awk -F'/' '{print $NF}')
        aws logs get-log-events \
            --log-group-name "/ecs/$TASK_FAMILY" \
            --log-stream-name "ecs/web/$TASK_ID" \
            --region $AWS_REGION \
            --limit 50 \
            --query 'events[*].message' \
            --output text 2>/dev/null || echo "   (Could not fetch logs)"
        
        return 1
    fi
}

# Confirm before proceeding
echo -e "${YELLOW}⚠️  This will run database migrations and initialize energy states.${NC}"
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""

# Step 1: Run migrations
run_ecs_task "bundle exec rails db:migrate" "Running database migrations"

echo ""

# Step 2: Initialize energy states
run_ecs_task "bundle exec rails agent_energy:init" "Initializing agent energy states"

echo ""

# Step 3: Show status
echo -e "${YELLOW}📊 Fetching current status...${NC}"
run_ecs_task "bundle exec rails agent_energy:status" "Agent energy status"

echo ""
echo "================================================"
echo -e "${GREEN}✅ Agent Collaboration System setup complete for $ENV!${NC}"
echo ""
echo "📍 Access points:"
if [ "$ENV" == "dev" ]; then
    echo "   - User Dashboard: https://dev.amoslabs.com/dashboard/energy"
    echo "   - Admin Dashboard: https://dev.amoslabs.com/admin/agent_collaboration/dashboard"
elif [ "$ENV" == "prod" ]; then
    echo "   - User Dashboard: https://app.amoslabs.com/dashboard/energy"
    echo "   - Admin Dashboard: https://app.amoslabs.com/admin/agent_collaboration/dashboard"
fi
echo ""

