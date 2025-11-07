#!/bin/bash
set -e

AWS_REGION=${AWS_REGION:-us-east-1}
CLUSTER_NAME="agent-marketing-dev-cluster"
TASK_FAMILY="agent-marketing-dev"
CONTAINER_NAME="agent-marketing-dev"
SERVICE_NAME="agent-marketing-dev"

echo "🗄️  Running database migrations on ECS (DEV environment)..."

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

echo "🌐 Network config:"
echo "   Subnets: $SUBNETS"
echo "   Security Groups: $SECURITY_GROUPS"

# Run migration task
echo "📋 Starting migration task..."
TASK_ARN=$(aws ecs run-task \
  --cluster $CLUSTER_NAME \
  --task-definition $TASK_DEFINITION \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUPS],assignPublicIp=DISABLED}" \
  --overrides "{\"containerOverrides\":[{\"name\":\"$CONTAINER_NAME\",\"command\":[\"./bin/rails\",\"db:migrate\"]}]}" \
  --region $AWS_REGION \
  --query 'tasks[0].taskArn' \
  --output text)

echo "🚀 Migration task started: $TASK_ARN"
echo "⏳ Waiting for migration to complete..."

aws ecs wait tasks-stopped --cluster $CLUSTER_NAME --tasks $TASK_ARN --region $AWS_REGION

# Check if migration succeeded
EXIT_CODE=$(aws ecs describe-tasks \
  --cluster $CLUSTER_NAME \
  --tasks $TASK_ARN \
  --region $AWS_REGION \
  --query 'tasks[0].containers[0].exitCode' \
  --output text)

if [ "$EXIT_CODE" -eq "0" ]; then
  echo "✅ Migrations completed successfully!"
  echo ""
  echo "📊 To view migration output, check CloudWatch Logs:"
  echo "   Log Group: /ecs/agent-marketing-dev"
  echo "   https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#logsV2:log-groups/log-group/%2Fecs%2Fagent-marketing-dev"
else
  echo "❌ Migration failed with exit code: $EXIT_CODE"
  echo ""
  echo "📊 Check CloudWatch logs for details:"
  echo "   Log Group: /ecs/agent-marketing-dev"
  echo "   https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#logsV2:log-groups/log-group/%2Fecs%2Fagent-marketing-dev"
  exit 1
fi

