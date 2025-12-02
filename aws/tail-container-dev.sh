#!/bin/bash

# Tail ECS Container Logs in Real-time (DEV environment)

echo "📋 Tailing ECS application logs (DEV)..."
echo "Press Ctrl+C to stop"
echo ""

# Configuration
AWS_REGION=${AWS_REGION:-us-east-1}
CLUSTER_NAME="agent-marketing-dev-cluster"
SERVICE_NAME="agent-marketing-dev"
LOG_GROUP="/ecs/agent-marketing-dev"

# Get the most recent running task
TASK_ARN=$(aws ecs list-tasks \
    --cluster $CLUSTER_NAME \
    --service-name $SERVICE_NAME \
    --desired-status RUNNING \
    --query 'taskArns[-1]' \
    --output text \
    --region $AWS_REGION)

if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" == "None" ]; then
    echo "❌ No running tasks found for service: $SERVICE_NAME"
    echo ""
    echo "💡 Tip: Check if the dev service is running:"
    echo "   aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION"
    exit 1
fi

# Extract container ID from task ARN
CONTAINER_ID=$(echo $TASK_ARN | awk -F'/' '{print $NF}')

echo "🔍 Task ARN: $TASK_ARN"
echo "📦 Container ID: $CONTAINER_ID"
echo "📝 Log Stream: ecs/agent-marketing-dev/$CONTAINER_ID"
echo ""

# Start time for log polling (last 2 minutes)
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    START_TIME=$(date -v-2M +%s)000
else
    # Linux
    START_TIME=$(date -d '2 minutes ago' +%s)000
fi

echo "Starting log stream..."
echo "----------------------------------------"

# Optional filter from command line
FILTER="${1:-}"

# Tail the logs with polling
while true; do
    # Get new log events
    LOGS=$(aws logs get-log-events \
        --log-group-name "$LOG_GROUP" \
        --log-stream-name "ecs/agent-marketing-dev/$CONTAINER_ID" \
        --start-time $START_TIME \
        --query 'events[*].[timestamp,message]' \
        --output text \
        --region $AWS_REGION 2>/dev/null)
    
    if [[ -n "$LOGS" ]]; then
        # Process and print new logs
        echo "$LOGS" | while IFS=$'\t' read -r timestamp message; do
            if [[ -n "$timestamp" && -n "$message" ]]; then
                # Convert timestamp to readable format
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    # macOS
                    READABLE_TIME=$(date -r $((timestamp/1000)) '+%Y-%m-%d %H:%M:%S')
                else
                    # Linux
                    READABLE_TIME=$(date -d "@$((timestamp/1000))" '+%Y-%m-%d %H:%M:%S')
                fi
                
                # Apply filter if provided
                if [[ -z "$FILTER" ]] || echo "$message" | grep -i -E "$FILTER" >/dev/null 2>&1; then
                    echo "[$READABLE_TIME] $message"
                fi
            fi
        done
        
        # Update start time for next iteration
        LAST_TIMESTAMP=$(echo "$LOGS" | tail -1 | cut -f1)
        if [[ -n "$LAST_TIMESTAMP" ]] && [[ "$LAST_TIMESTAMP" != "None" ]]; then
            START_TIME=$((LAST_TIMESTAMP + 1))
        fi
    fi
    
    # Wait before next poll
    sleep 1
done

