#!/bin/bash
set -e

# Configuration
AWS_REGION=${AWS_REGION:-us-east-1}
APP_NAME="agent-marketing"
ECR_REPO_NAME=$APP_NAME
CLUSTER_NAME="${APP_NAME}-cluster"
SERVICE_NAME=$APP_NAME

echo "🚀 Starting AWS deployment for $APP_NAME"

# Step 1: Build and push Docker image
echo "📦 Building Docker image for linux/amd64..."
docker build --platform linux/amd64 -t $APP_NAME .

# Get ECR login token
echo "🔐 Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $(aws sts get-caller-identity --query Account --output text).dkr.ecr.$AWS_REGION.amazonaws.com

# Get ECR repository URL
ECR_REPO_URL=$(aws ecr describe-repositories --repository-names $ECR_REPO_NAME --region $AWS_REGION --query 'repositories[0].repositoryUri' --output text)

# Tag and push image
echo "📤 Pushing image to ECR..."
docker tag $APP_NAME:latest $ECR_REPO_URL:latest
docker push $ECR_REPO_URL:latest

# Step 2: Register new task definition
echo "📝 Registering new task definition..."
TASK_DEFINITION_ARN=$(aws ecs register-task-definition \
  --cli-input-json file://aws/task-definition.json \
  --region $AWS_REGION \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

# Step 3: Update ECS service with new task definition
echo "🔄 Updating ECS service..."
aws ecs update-service \
  --cluster $CLUSTER_NAME \
  --service $SERVICE_NAME \
  --task-definition $TASK_DEFINITION_ARN \
  --enable-execute-command \
  --force-new-deployment \
  --region $AWS_REGION

echo "⏳ Waiting for service to stabilize..."
aws ecs wait services-stable \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --region $AWS_REGION

echo "✅ Deployment complete!"

# Get ALB URL
ALB_DNS=$(aws elbv2 describe-load-balancers --region $AWS_REGION --query "LoadBalancers[?contains(LoadBalancerName, '$APP_NAME')].DNSName" --output text)
echo "🌐 Application available at: https://$ALB_DNS"
