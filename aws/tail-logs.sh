#!/bin/bash

# AWS ECS Log Tailer Script
# Usage: ./aws/tail-logs.sh [minutes] [filter_pattern]
# Example: ./aws/tail-logs.sh 10 "error"
# Example: ./aws/tail-logs.sh 30 "campaign|scout"

set -e

# Configuration
AWS_REGION=${AWS_REGION:-us-east-1}
LOG_GROUP="/ecs/agent-marketing"
MINUTES=${1:-5}  # Default to 5 minutes
FILTER=${2:-""}  # Optional filter pattern

echo "📋 ECS Log Viewer"
echo "==================="
echo "⏰ Time range: Last $MINUTES minutes"
echo "🔍 Filter: ${FILTER:-None}"
echo ""

# Get the most recent log stream
echo "🔄 Getting latest log stream..."
LOG_STREAM=$(aws logs describe-log-streams \
  --log-group-name $LOG_GROUP \
  --order-by LastEventTime \
  --descending \
  --limit 1 \
  --region $AWS_REGION \
  --query 'logStreams[0].logStreamName' \
  --output text)

echo "📍 Log stream: $LOG_STREAM"
echo ""

# Calculate start time
START_TIME=$(date -u -v-${MINUTES}M +%s)000

# Function to tail logs with optional filter
tail_logs() {
  if [ -z "$FILTER" ]; then
    # No filter - show all logs
    aws logs get-log-events \
      --log-group-name $LOG_GROUP \
      --log-stream-name $LOG_STREAM \
      --start-time $START_TIME \
      --region $AWS_REGION \
      | jq -r '.events[].message'
  else
    # Apply filter
    aws logs get-log-events \
      --log-group-name $LOG_GROUP \
      --log-stream-name $LOG_STREAM \
      --start-time $START_TIME \
      --region $AWS_REGION \
      | jq -r '.events[].message' \
      | grep -i -E "$FILTER"
  fi
}

# Check if we want to follow logs
if [ "$3" == "--follow" ] || [ "$3" == "-f" ]; then
  echo "📡 Following logs (Ctrl+C to stop)..."
  echo "==================="
  
  while true; do
    tail_logs
    sleep 5
  done
else
  echo "📄 Showing logs..."
  echo "==================="
  tail_logs
  echo ""
  echo "💡 Tip: Add --follow or -f to tail logs continuously"
  echo "   Example: ./aws/tail-logs.sh 5 'error' --follow"
fi
