#!/bin/bash
# Deploy updated task definition with encryption secrets
# Run this after create-encryption-secrets.sh

set -e

AWS_REGION=${AWS_REGION:-us-east-1}
CLUSTER="agent-marketing-cluster"
SERVICE="agent-marketing-service"

echo "🔐 Deploying encryption fix to production..."
echo ""

# Step 1: Register the new task definition
echo "📋 Registering updated task definition..."
TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json file://aws/task-definition.json \
  --region $AWS_REGION \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

echo "   ✅ Registered: $TASK_DEF_ARN"
echo ""

# Step 2: Update the service
echo "🚀 Updating ECS service..."
aws ecs update-service \
  --cluster $CLUSTER \
  --service $SERVICE \
  --task-definition agent-marketing \
  --region $AWS_REGION \
  --query 'service.deployments[0].status' \
  --output text

echo "   ✅ Service update initiated"
echo ""

# Step 3: Wait for deployment
echo "⏳ Waiting for deployment to stabilize (this may take 2-5 minutes)..."
aws ecs wait services-stable \
  --cluster $CLUSTER \
  --services $SERVICE \
  --region $AWS_REGION

echo ""
echo "✅ Deployment complete! Encryption is now active."
echo ""
echo "🧪 Test by connecting a QuickBooks integration."

