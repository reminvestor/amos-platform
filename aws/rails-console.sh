#!/bin/bash
# Script to open Rails console on AWS ECS

# Get the task ARN for the running web container
TASK_ARN=$(aws ecs list-tasks \
  --cluster agent-marketing-cluster \
  --service-name agent-marketing \
  --desired-status RUNNING \
  --query 'taskArns[0]' \
  --output text \
  --region us-east-1)

if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" == "None" ]; then
  echo "❌ No running tasks found"
  exit 1
fi

echo "📦 Found running task: ${TASK_ARN}"
echo "🚀 Opening Rails console..."
echo ""

# Execute Rails console in the container
aws ecs execute-command \
  --cluster agent-marketing-cluster \
  --task "${TASK_ARN}" \
  --container agent-marketing \
  --command "bin/rails console" \
  --interactive \
  --region us-east-1

