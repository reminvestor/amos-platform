#!/bin/bash
set -e

AWS_REGION=${AWS_REGION:-us-east-1}
CLUSTER_NAME="agent-marketing-cluster"
TASK_FAMILY="agent-marketing"

echo "🗄️  Running database migrations on ECS..."

# Get the latest task definition
TASK_DEFINITION=$(aws ecs describe-task-definition \
  --task-definition $TASK_FAMILY \
  --region $AWS_REGION \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

# Get subnet and security group from the service
SERVICE_CONFIG=$(aws ecs describe-services \
  --cluster $CLUSTER_NAME \
  --services agent-marketing \
  --region $AWS_REGION \
  --query 'services[0].networkConfiguration.awsvpcConfiguration' \
  --output json)

SUBNETS=$(echo $SERVICE_CONFIG | jq -r '.subnets | join(",")')
SECURITY_GROUPS=$(echo $SERVICE_CONFIG | jq -r '.securityGroups | join(",")')

# Run migration task
echo "📋 Starting migration task..."
TASK_ARN=$(aws ecs run-task \
  --cluster $CLUSTER_NAME \
  --task-definition $TASK_DEFINITION \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUPS],assignPublicIp=DISABLED}" \
  --overrides '{"containerOverrides":[{"name":"agent-marketing","command":["bundle","exec","rails","db:migrate"]}]}' \
  --region $AWS_REGION \
  --query 'tasks[0].taskArn' \
  --output text)

echo "⏳ Waiting for migration task ($TASK_ARN) to complete..."
aws ecs wait tasks-stopped --cluster $CLUSTER_NAME --tasks $TASK_ARN --region $AWS_REGION

# Get full task details
TASK_DETAILS=$(aws ecs describe-tasks \
  --cluster $CLUSTER_NAME \
  --tasks $TASK_ARN \
  --region $AWS_REGION \
  --output json)

# Extract exit code and reasons
EXIT_CODE=$(echo $TASK_DETAILS | jq -r '.tasks[0].containers[0].exitCode // "null"')
STOPPED_REASON=$(echo $TASK_DETAILS | jq -r '.tasks[0].stoppedReason // "Unknown"')
STOP_CODE=$(echo $TASK_DETAILS | jq -r '.tasks[0].stopCode // "Unknown"')
CONTAINER_REASON=$(echo $TASK_DETAILS | jq -r '.tasks[0].containers[0].reason // "None"')

echo "Task Execution Details:"
echo "Exit Code: $EXIT_CODE"
echo "Stop Code: $STOP_CODE"
echo "Stopped Reason: $STOPPED_REASON"
echo "Container Reason: $CONTAINER_REASON"

if [ "$EXIT_CODE" == "0" ]; then
  echo "✅ Migrations completed successfully!"
else
  echo "❌ Migration failed."
  if [ "$EXIT_CODE" == "null" ]; then
    echo "The container did not return an exit code. This usually means it failed to start."
  fi
  echo "Check CloudWatch logs for details"
  exit 1
fi
