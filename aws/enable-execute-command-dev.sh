#!/bin/bash
# Script to enable ECS Execute Command on the dev service
# This will force a new deployment with execute command enabled

set -e

AWS_REGION=${AWS_REGION:-us-east-1}
CLUSTER_NAME="agent-marketing-dev-cluster"
SERVICE_NAME="agent-marketing-dev"

echo "🔧 Enabling ECS Execute Command for dev service..."
echo ""

# Check if service exists
SERVICE_EXISTS=$(aws ecs describe-services \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --region $AWS_REGION \
  --query 'services[0].status' \
  --output text 2>/dev/null || echo "None")

if [ "$SERVICE_EXISTS" == "None" ] || [ -z "$SERVICE_EXISTS" ]; then
  echo "❌ Service $SERVICE_NAME not found in cluster $CLUSTER_NAME"
  exit 1
fi

echo "📋 Current service status:"
aws ecs describe-services \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --region $AWS_REGION \
  --query 'services[0].[serviceName,status,enableExecuteCommand]' \
  --output table

echo ""
echo "🔄 Updating service to enable execute command..."
echo "   This will force a new deployment with execute command enabled."
echo ""

# Update the service to enable execute command
aws ecs update-service \
  --cluster $CLUSTER_NAME \
  --service $SERVICE_NAME \
  --enable-execute-command \
  --force-new-deployment \
  --region $AWS_REGION \
  --query 'service.[serviceName,status,enableExecuteCommand]' \
  --output table

echo ""
echo "⏳ Waiting for service to stabilize (this may take a few minutes)..."
echo "   New tasks will be started with execute command enabled."
echo ""

# Wait for service to stabilize
aws ecs wait services-stable \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --region $AWS_REGION

echo ""
echo "✅ Service updated successfully!"
echo ""
echo "📋 Updated service status:"
aws ecs describe-services \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --region $AWS_REGION \
  --query 'services[0].[serviceName,status,enableExecuteCommand]' \
  --output table

echo ""
echo "💡 You can now use ./aws/rails-console-dev.sh to access the Rails console"
echo ""

