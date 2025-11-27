#!/bin/bash
# =============================================================================
# Agent Collaboration System - Run Migration Only (AWS)
# =============================================================================
# Quick script to run just the database migrations in AWS.
# Use this when you only need to update the schema without full setup.
#
# Usage:
#   ./scripts/collaboration/run_migration_aws.sh dev
#   ./scripts/collaboration/run_migration_aws.sh prod
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

echo "🗄️  Running migrations on $ENV..."

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

# Run migration task
TASK_ARN=$(aws ecs run-task \
    --cluster $CLUSTER \
    --task-definition $TASK_DEF \
    --network-configuration "$NETWORK_CONFIG" \
    --launch-type FARGATE \
    --overrides '{
        "containerOverrides": [{
            "name": "web",
            "command": ["bash", "-c", "bundle exec rails db:migrate"]
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
    echo -e "${GREEN}✅ Migrations complete!${NC}"
else
    echo -e "${RED}❌ Migration failed (exit code: $EXIT_CODE)${NC}"
    exit 1
fi

