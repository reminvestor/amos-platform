#!/bin/bash
# Script to open Rails console on AWS ECS (DEV environment)

AWS_REGION=${AWS_REGION:-us-east-1}
CLUSTER_NAME="agent-marketing-dev-cluster"
SERVICE_NAME="agent-marketing-dev"
CONTAINER_NAME="agent-marketing-dev"

echo "🔍 Finding running task in DEV environment..."

# Get the task ARN for the running web container
TASK_ARN=$(aws ecs list-tasks \
  --cluster $CLUSTER_NAME \
  --service-name $SERVICE_NAME \
  --desired-status RUNNING \
  --query 'taskArns[0]' \
  --output text \
  --region $AWS_REGION)

if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" == "None" ]; then
  echo "❌ No running tasks found in cluster: $CLUSTER_NAME"
  echo ""
  echo "💡 Tip: Check if the dev service is running:"
  echo "   aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION"
  exit 1
fi

echo "📦 Found running task: ${TASK_ARN}"
echo "🚀 Opening Rails console in DEV..."
echo ""
echo "⚠️  Note: This is the DEV environment database"
echo ""

# Execute Rails console in the container
aws ecs execute-command \
  --cluster $CLUSTER_NAME \
  --task "${TASK_ARN}" \
  --container $CONTAINER_NAME \
  --command "bin/rails console" \
  --interactive \
  --region $AWS_REGION

