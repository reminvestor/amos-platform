#!/bin/bash
# Configure ECS cluster to support Execute Command with CloudWatch logging
set -e

AWS_REGION=${AWS_REGION:-us-east-1}
CLUSTER_NAME="agent-marketing-dev-cluster"

echo "🔧 Configuring ECS Execute Command logging for dev cluster..."
echo ""

# Update cluster configuration to enable execute command logging
echo "📋 Updating cluster configuration..."
aws ecs update-cluster \
  --cluster $CLUSTER_NAME \
  --region $AWS_REGION \
  --configuration "executeCommandConfiguration={logging=DEFAULT}" \
  --query 'cluster.[clusterName,configuration.executeCommandConfiguration.logging]' \
  --output table

echo ""
echo "✅ Cluster configuration updated!"
echo ""
echo "💡 Now try running: ./aws/rails-console-dev.sh"
echo ""

