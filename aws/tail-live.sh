#!/bin/bash

# Live tail of ECS logs
# Usage: ./aws/tail-live.sh [filter_pattern]
# Example: ./aws/tail-live.sh
# Example: ./aws/tail-live.sh "error"
# Example: ./aws/tail-live.sh "campaign|scout"

set -e

AWS_REGION=${AWS_REGION:-us-east-1}
LOG_GROUP="/ecs/agent-marketing"
FILTER=${1:-""}  # Optional grep filter

echo "📡 ECS Live Log Tail"
echo "===================="
echo "🔍 Filter: ${FILTER:-None}"
echo "⏹️  Press Ctrl+C to stop"
echo ""

# Get the most recent log stream
LOG_STREAM=$(aws logs describe-log-streams \
  --log-group-name $LOG_GROUP \
  --order-by LastEventTime \
  --descending \
  --limit 1 \
  --region $AWS_REGION \
  --query 'logStreams[0].logStreamName' \
  --output text)

echo "📍 Log stream: $LOG_STREAM"
echo "===================="
echo ""

# Function to get and display new logs
LAST_TOKEN=""
LAST_TIMESTAMP=""

tail_logs() {
  if [ -z "$LAST_TIMESTAMP" ]; then
    # First run - get logs from last 2 minutes
    START_TIME=$(date -u -v-2M +%s)000
    RESPONSE=$(aws logs get-log-events \
      --log-group-name $LOG_GROUP \
      --log-stream-name $LOG_STREAM \
      --start-time $START_TIME \
      --region $AWS_REGION)
  else
    # Subsequent runs - get new logs since last timestamp
    RESPONSE=$(aws logs get-log-events \
      --log-group-name $LOG_GROUP \
      --log-stream-name $LOG_STREAM \
      --start-time $LAST_TIMESTAMP \
      --region $AWS_REGION)
  fi
  
  # Get the timestamp of the last event
  NEW_TIMESTAMP=$(echo "$RESPONSE" | jq -r '.events[-1].timestamp // empty')
  if [ -n "$NEW_TIMESTAMP" ]; then
    # Add 1 millisecond to avoid duplicates
    LAST_TIMESTAMP=$((NEW_TIMESTAMP + 1))
  fi
  
  # Display logs with optional filter
  if [ -z "$FILTER" ]; then
    echo "$RESPONSE" | jq -r '.events[].message' | grep -v "^$" || true
  else
    echo "$RESPONSE" | jq -r '.events[].message' | grep -i -E "$FILTER" || true
  fi
}

# Main loop
while true; do
  tail_logs
  sleep 2
done
