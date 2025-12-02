#!/bin/bash
# Deploy updated task definition to dev with ECS Exec support
set -e

AWS_REGION=${AWS_REGION:-us-east-1}
APP_NAME="agent-marketing-dev"
ECR_REPO_NAME=$APP_NAME
CLUSTER_NAME="${APP_NAME}-cluster"
SERVICE_NAME=$APP_NAME

echo "🚀 Deploying to DEV with ECS Exec enabled"
echo ""

# Step 1: Get current task definition
echo "📋 Fetching current task definition..."
TASK_DEF=$(aws ecs describe-task-definition \
  --task-definition $APP_NAME \
  --region $AWS_REGION \
  --query 'taskDefinition')

# Extract the image URL from current task definition
IMAGE_URL=$(echo $TASK_DEF | jq -r '.containerDefinitions[0].image')

echo "📦 Current image: $IMAGE_URL"
echo ""

# Step 2: Create new task definition with linuxParameters
echo "📝 Creating updated task definition with ECS Exec support..."

# Get essential details from current task definition
TASK_ROLE_ARN=$(echo $TASK_DEF | jq -r '.taskRoleArn')
EXECUTION_ROLE_ARN=$(echo $TASK_DEF | jq -r '.executionRoleArn')
CPU=$(echo $TASK_DEF | jq -r '.cpu')
MEMORY=$(echo $TASK_DEF | jq -r '.memory')

# Create new task definition JSON with linuxParameters
NEW_TASK_DEF=$(echo $TASK_DEF | jq '
  .containerDefinitions[0].linuxParameters = {
    "initProcessEnabled": true
  } |
  del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)
')

# Save to temp file
echo "$NEW_TASK_DEF" > /tmp/task-def-update.json

# Register new task definition
echo "📤 Registering new task definition..."
NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json file:///tmp/task-def-update.json \
  --region $AWS_REGION \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

echo "✅ New task definition: $NEW_TASK_DEF_ARN"
echo ""

# Step 3: Update service
echo "🔄 Updating ECS service..."
aws ecs update-service \
  --cluster $CLUSTER_NAME \
  --service $SERVICE_NAME \
  --task-definition $NEW_TASK_DEF_ARN \
  --enable-execute-command \
  --force-new-deployment \
  --region $AWS_REGION \
  --query 'service.[serviceName,status,enableExecuteCommand]' \
  --output table

echo ""
echo "⏳ Waiting for service to stabilize (this may take a few minutes)..."
aws ecs wait services-stable \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --region $AWS_REGION

echo ""
echo "✅ Deployment complete!"
echo ""
echo "💡 Wait about 30 seconds for the SSM agent to initialize, then run:"
echo "   ./aws/rails-console-dev.sh"
echo ""

# Clean up
rm -f /tmp/task-def-update.json

