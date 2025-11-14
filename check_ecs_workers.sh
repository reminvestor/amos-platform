#!/bin/bash

echo "Checking ECS Workers Status..."

# List all services in the cluster
echo "=== ECS Services ==="
aws ecs list-services --cluster agent-marketing-cluster

# Check worker service status
echo -e "\n=== Worker Service Details ==="
aws ecs describe-services \
  --cluster agent-marketing-cluster \
  --services agent-marketing-worker \
  --query 'services[0].{status:status,runningCount:runningCount,desiredCount:desiredCount,taskDefinition:taskDefinition}'

# Get recent tasks for worker service
echo -e "\n=== Recent Worker Tasks ==="
aws ecs list-tasks \
  --cluster agent-marketing-cluster \
  --service-name agent-marketing-worker \
  --desired-status RUNNING

# Check CloudWatch logs for worker errors
echo -e "\n=== Recent Worker Logs (last 10 minutes) ==="
aws logs filter-log-events \
  --log-group-name /ecs/agent-marketing \
  --log-stream-name-prefix worker \
  --start-time $(($(date +%s) * 1000 - 600000)) \
  --filter-pattern "ERROR"

echo -e "\n=== Checking for Document Pipeline Jobs ==="
aws logs filter-log-events \
  --log-group-name /ecs/agent-marketing \
  --log-stream-name-prefix worker \
  --start-time $(($(date +%s) * 1000 - 600000)) \
  --filter-pattern "DocumentPipelineJob"
