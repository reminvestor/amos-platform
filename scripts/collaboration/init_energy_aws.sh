#!/bin/bash
# =============================================================================
# Agent Collaboration System - Initialize Energy States (AWS)
# =============================================================================
# Quick script to initialize energy states for all agents in AWS.
# Use this after migrations to set up the energy economy.
#
# Usage:
#   ./scripts/collaboration/init_energy_aws.sh dev
#   ./scripts/collaboration/init_energy_aws.sh prod
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

echo "🔋 Initializing energy states on $ENV..."

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

# Run init task
TASK_ARN=$(aws ecs run-task \
    --cluster $CLUSTER \
    --task-definition $TASK_DEF \
    --network-configuration "$NETWORK_CONFIG" \
    --launch-type FARGATE \
    --overrides '{
        "containerOverrides": [{
            "name": "web",
            "command": ["bash", "-c", "bundle exec rails agent_energy:init"]
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

EXIT_CODE=$(aws ecs describe-tasks \
    --cluster $CLUSTER \
    --tasks $TASK_ARN \
    --region $AWS_REGION \
    --query 'tasks[0].containers[0].exitCode' \
    --output text)

if [ "$EXIT_CODE" == "0" ]; then
    echo -e "${GREEN}✅ Energy states initialized!${NC}"
else
    echo -e "${RED}❌ Initialization failed (exit code: $EXIT_CODE)${NC}"
    exit 1
fi

