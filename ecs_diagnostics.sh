#!/bin/bash
# AWS ECS Deployment Diagnostics Commands

# First, set your cluster and service names
# You may need to modify these based on your setup
CLUSTER_NAME="agent-marketing-dev"  # Update this
SERVICE_NAME="agent-marketing-dev"  # Update this
REGION="us-east-1"  # Update if needed

echo "====================================================
ECS DEPLOYMENT DIAGNOSTIC COMMANDS
====================================================

1. LIST ALL ECS CLUSTERS:
aws ecs list-clusters --region $REGION

2. CHECK SERVICE STATUS AND DEPLOYMENTS:
aws ecs describe-services \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --region $REGION \
  --query "services[0].[serviceName,status,desiredCount,runningCount,pendingCount,deployments[*].[status,taskDefinition,desiredCount,runningCount,pendingCount]]" \
  --output table

3. LIST RUNNING TASKS:
aws ecs list-tasks \
  --cluster $CLUSTER_NAME \
  --service-name $SERVICE_NAME \
  --region $REGION

4. GET STUCK TASK DETAILS:
# First get task ARNs
TASKS=$(aws ecs list-tasks --cluster $CLUSTER_NAME --service-name $SERVICE_NAME --region $REGION --query "taskArns[]" --output text)

# Then describe them
aws ecs describe-tasks \
  --cluster $CLUSTER_NAME \
  --tasks $TASKS \
  --region $REGION \
  --query "tasks[*].[taskArn,lastStatus,desiredStatus,stoppedReason]" \
  --output table

5. CHECK CLOUDFORMATION STACKS:
aws cloudformation list-stacks \
  --region $REGION \
  --stack-status-filter DELETE_IN_PROGRESS DELETE_FAILED \
  --query "StackSummaries[?contains(StackName, 'agent-marketing')].[StackName,StackStatus,StackStatusReason]" \
  --output table

6. FORCE STOP ALL TASKS (USE WITH CAUTION):
aws ecs list-tasks \
  --cluster $CLUSTER_NAME \
  --service-name $SERVICE_NAME \
  --region $REGION \
  --query "taskArns[]" \
  --output text | xargs -I {} aws ecs stop-task --cluster $CLUSTER_NAME --task {} --region $REGION

7. UPDATE SERVICE TO FORCE NEW DEPLOYMENT:
aws ecs update-service \
  --cluster $CLUSTER_NAME \
  --service $SERVICE_NAME \
  --force-new-deployment \
  --region $REGION

8. CHECK ECS EVENTS FOR ERRORS:
aws ecs describe-services \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --region $REGION \
  --query "services[0].events[0:10].[createdAt,message]" \
  --output table
"

# To run specific commands, copy and paste them
# Make sure to update CLUSTER_NAME, SERVICE_NAME, and REGION first!
