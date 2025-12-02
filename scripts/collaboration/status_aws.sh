#!/bin/bash
# =============================================================================
# Agent Collaboration System - Check Status (AWS)
# =============================================================================
# Quick script to check the status of the collaboration system in AWS.
#
# Usage:
#   ./scripts/collaboration/status_aws.sh dev
#   ./scripts/collaboration/status_aws.sh prod
# =============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ -z "$1" ]; then
    echo -e "${RED}❌ Usage: $0 <environment>${NC}"
    echo "   Environments: dev, prod"
    exit 1
fi

ENV=$1
AWS_REGION="${AWS_REGION:-us-east-1}"

if [ "$ENV" == "dev" ]; then
    CLUSTER="agent-marketing-dev"
    TASK_FAMILY="agent-marketing-dev"
elif [ "$ENV" == "prod" ]; then
    CLUSTER="agent-marketing-prod"
    TASK_FAMILY="agent-marketing-prod"
else
    echo -e "${RED}❌ Invalid environment: $ENV${NC}"
    exit 1
fi

echo "📊 Checking collaboration system status on $ENV..."
echo ""

# Get task definition and network config
TASK_DEF=$(aws ecs describe-task-definition \
    --task-definition $TASK_FAMILY \
    --region $AWS_REGION \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

SERVICE="${TASK_FAMILY}-service"
NETWORK_CONFIG=$(aws ecs describe-services \
    --cluster $CLUSTER \
    --services $SERVICE \
    --region $AWS_REGION \
    --query 'services[0].networkConfiguration' \
    --output json)

# Run status task
TASK_ARN=$(aws ecs run-task \
    --cluster $CLUSTER \
    --task-definition $TASK_DEF \
    --network-configuration "$NETWORK_CONFIG" \
    --launch-type FARGATE \
    --overrides '{
        "containerOverrides": [{
            "name": "web",
            "command": ["bash", "-c", "bundle exec rails agent_energy:status && echo && bundle exec rails agent_energy:school_stats && echo && bundle exec rails agent_energy:collab_stats"]
        }]
    }' \
    --region $AWS_REGION \
    --query 'tasks[0].taskArn' \
    --output text)

echo -e "${BLUE}Task ARN: $TASK_ARN${NC}"
echo "Waiting for task to complete..."

aws ecs wait tasks-stopped \
    --cluster $CLUSTER \
    --tasks $TASK_ARN \
    --region $AWS_REGION

# Get logs
TASK_ID=$(echo $TASK_ARN | awk -F'/' '{print $NF}')
echo ""
echo -e "${YELLOW}📋 Output:${NC}"
echo "----------------------------------------"

aws logs get-log-events \
    --log-group-name "/ecs/$TASK_FAMILY" \
    --log-stream-name "ecs/web/$TASK_ID" \
    --region $AWS_REGION \
    --query 'events[*].message' \
    --output text 2>/dev/null || echo "(Could not fetch logs - check CloudWatch)"

echo "----------------------------------------"
echo -e "${GREEN}✅ Status check complete${NC}"

