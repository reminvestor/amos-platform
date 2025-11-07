#!/bin/bash
# Script to wait for ECS task to be ready for execute command

set -e

AWS_REGION=${AWS_REGION:-us-east-1}
CLUSTER_NAME="agent-marketing-dev-cluster"
SERVICE_NAME="agent-marketing-dev"
MAX_ATTEMPTS=30
WAIT_SECONDS=10

echo "⏳ Waiting for dev task to be ready for execute command..."
echo ""

for ((i=1; i<=MAX_ATTEMPTS; i++)); do
  echo "🔍 Attempt $i/$MAX_ATTEMPTS..."
  
  # Get the most recent running task
  TASK_ARN=$(aws ecs list-tasks \
    --cluster $CLUSTER_NAME \
    --service-name $SERVICE_NAME \
    --desired-status RUNNING \
    --query 'taskArns[0]' \
    --output text \
    --region $AWS_REGION 2>/dev/null)
  
  if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" == "None" ]; then
    echo "   ⚠️  No running tasks found yet, waiting..."
    sleep $WAIT_SECONDS
    continue
  fi
  
  # Check if task has execute command enabled
  EXEC_ENABLED=$(aws ecs describe-tasks \
    --cluster $CLUSTER_NAME \
    --tasks "$TASK_ARN" \
    --region $AWS_REGION \
    --query 'tasks[0].enableExecuteCommand' \
    --output text 2>/dev/null)
  
  if [ "$EXEC_ENABLED" != "True" ]; then
    echo "   ⚠️  Execute command not enabled on this task, waiting for new task..."
    sleep $WAIT_SECONDS
    continue
  fi
  
  # Check task health status
  HEALTH_STATUS=$(aws ecs describe-tasks \
    --cluster $CLUSTER_NAME \
    --tasks "$TASK_ARN" \
    --region $AWS_REGION \
    --query 'tasks[0].healthStatus' \
    --output text 2>/dev/null)
  
  LAST_STATUS=$(aws ecs describe-tasks \
    --cluster $CLUSTER_NAME \
    --tasks "$TASK_ARN" \
    --region $AWS_REGION \
    --query 'tasks[0].lastStatus' \
    --output text 2>/dev/null)
  
  echo "   Task Status: $LAST_STATUS"
  echo "   Health Status: $HEALTH_STATUS"
  echo "   Execute Command: $EXEC_ENABLED"
  
  # Task is RUNNING and execute command is enabled - try a test connection
  if [ "$LAST_STATUS" == "RUNNING" ] && [ "$EXEC_ENABLED" == "True" ]; then
    # Give it a bit more time for the SSM agent to fully initialize
    if [ $i -lt 3 ]; then
      echo "   ⏳ Task is running, waiting for SSM agent to initialize..."
      sleep $WAIT_SECONDS
      continue
    fi
    
    # Try to execute a simple command to verify connectivity
    echo "   🧪 Testing execute command connectivity..."
    if aws ecs execute-command \
      --cluster $CLUSTER_NAME \
      --task "$TASK_ARN" \
      --container agent-marketing-dev \
      --command "echo 'test'" \
      --region $AWS_REGION \
      --interactive 2>&1 | grep -q "Starting session"; then
      
      echo ""
      echo "✅ Task is ready for execute command!"
      echo ""
      echo "📦 Task ARN: $TASK_ARN"
      echo ""
      echo "💡 You can now run: ./aws/rails-console-dev.sh"
      echo ""
      exit 0
    else
      echo "   ⚠️  Execute command not responding yet, waiting..."
      sleep $WAIT_SECONDS
      continue
    fi
  fi
  
  sleep $WAIT_SECONDS
done

echo ""
echo "❌ Task did not become ready for execute command after $((MAX_ATTEMPTS * WAIT_SECONDS)) seconds"
echo ""
echo "💡 Things to check:"
echo "   1. Check task logs: ./aws/tail-dev.sh"
echo "   2. Check task status: aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks <TASK_ARN> --region $AWS_REGION"
echo "   3. Verify the task definition has execute command enabled"
echo ""
exit 1

