#!/bin/bash

# Simple production log tailer
# Usage: ./aws/tail-prod.sh [filter]
# Example: ./aws/tail-prod.sh
# Example: ./aws/tail-prod.sh "error"
# Example: ./aws/tail-prod.sh "campaign|scout"

set -e

AWS_REGION=${AWS_REGION:-us-east-1}
LOG_GROUP="/ecs/agent-marketing"
FILTER=${1:-""}

echo "📡 Production Log Stream"
echo "========================"
echo "🔍 Filter: ${FILTER:-None}"
echo "⏹️  Press Ctrl+C to stop"
echo ""

# Check AWS CLI version
AWS_VERSION=$(aws --version 2>&1 | cut -d' ' -f1 | cut -d'/' -f2 | cut -d'.' -f1)

if [ "$AWS_VERSION" = "2" ]; then
  # AWS CLI v2 - use built-in tail
  echo "Using AWS CLI v2 tail command..."
  if [ -z "$FILTER" ]; then
    aws logs tail $LOG_GROUP --follow --region $AWS_REGION --format short
  else
    aws logs tail $LOG_GROUP --follow --region $AWS_REGION --format short | grep -i -E "$FILTER" --line-buffered
  fi
else
  # AWS CLI v1 - use custom tail logic
  echo "Using AWS CLI v1 with custom tail..."
  
  # Get initial logs from last 1 minute
  LAST_TIME=$(date -u -v-1M +%s)000
  
  while true; do
    # Get new logs since last check
    LOGS=$(aws logs filter-log-events \
      --log-group-name $LOG_GROUP \
      --start-time $LAST_TIME \
      --region $AWS_REGION 2>/dev/null | jq -r '.events[].message' 2>/dev/null)
    
    # Update last time to current time for next iteration
    LAST_TIME=$(date +%s)000
    
    # Display logs with optional filter
    if [ -n "$LOGS" ]; then
      if [ -z "$FILTER" ]; then
        echo "$LOGS"
      else
        echo "$LOGS" | grep -i -E "$FILTER" || true
      fi
    fi
    
    # Wait before next check
    sleep 2
  done
fi
