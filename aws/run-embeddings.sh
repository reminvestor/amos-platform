#!/bin/bash
set -e

AWS_REGION=${AWS_REGION:-us-east-1}
CLUSTER_NAME="agent-marketing-cluster"
TASK_FAMILY="agent-marketing"
SERVICE_NAME="agent-marketing"

echo "🧠 Running embeddings update on ECS (PROD environment)..."

# Get the latest task definition
TASK_DEFINITION=$(aws ecs describe-task-definition \
  --task-definition $TASK_FAMILY \
  --region $AWS_REGION \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

echo "📋 Using task definition: $TASK_DEFINITION"

# Get subnet and security group from the service
SERVICE_CONFIG=$(aws ecs describe-services \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --region $AWS_REGION \
  --query 'services[0].networkConfiguration.awsvpcConfiguration' \
  --output json)

SUBNETS=$(echo $SERVICE_CONFIG | jq -r '.subnets | join(",")')
SECURITY_GROUPS=$(echo $SERVICE_CONFIG | jq -r '.securityGroups | join(",")')

echo "Using Subnets: $SUBNETS"
echo "Using Security Groups: $SECURITY_GROUPS"

# Run embeddings update task
echo "📋 Starting embeddings update task..."
TASK_ARN=$(aws ecs run-task \
  --cluster $CLUSTER_NAME \
  --task-definition $TASK_DEFINITION \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUPS],assignPublicIp=DISABLED}" \
  --overrides '{"containerOverrides":[{"name":"agent-marketing","command":["bundle","exec","rails","embeddings:update_all"]}]}' \
  --region $AWS_REGION \
  --query 'tasks[0].taskArn' \
  --output text)

echo "⏳ Waiting for embeddings task ($TASK_ARN) to complete..."
aws ecs wait tasks-stopped --cluster $CLUSTER_NAME --tasks $TASK_ARN --region $AWS_REGION

# Get task details
TASK_DETAILS=$(aws ecs describe-tasks \
  --cluster $CLUSTER_NAME \
  --tasks $TASK_ARN \
  --region $AWS_REGION)

EXIT_CODE=$(echo $TASK_DETAILS | jq -r '.tasks[0].containers[0].exitCode // "None"')
STOP_CODE=$(echo $TASK_DETAILS | jq -r '.tasks[0].stopCode // "None"')
STOPPED_REASON=$(echo $TASK_DETAILS | jq -r '.tasks[0].stoppedReason // "None"')
CONTAINER_REASON=$(echo $TASK_DETAILS | jq -r '.tasks[0].containers[0].reason // "None"')

echo "Task Execution Details:"
echo "Exit Code: $EXIT_CODE"
echo "Stop Code: $STOP_CODE"
echo "Stopped Reason: $STOPPED_REASON"
echo "Container Reason: $CONTAINER_REASON"

if [ "$EXIT_CODE" == "0" ]; then
  echo "✅ Embeddings updated successfully!"
else
  echo "❌ Embeddings update failed!"
  exit 1
fi

