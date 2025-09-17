#!/bin/bash

# AWS CloudWatch Log Search Script
# Usage: ./aws/search-logs.sh [minutes] "filter pattern"
# Example: ./aws/search-logs.sh 60 "ERROR"
# Example: ./aws/search-logs.sh 120 "campaign AND viewer"

set -e

# Configuration
AWS_REGION=${AWS_REGION:-us-east-1}
LOG_GROUP="/ecs/agent-marketing"
MINUTES=${1:-30}  # Default to 30 minutes
FILTER_PATTERN=${2:-""}  # CloudWatch filter pattern

echo "🔍 CloudWatch Log Search"
echo "========================"
echo "⏰ Time range: Last $MINUTES minutes"
echo "🔍 Filter pattern: ${FILTER_PATTERN:-All logs}"
echo ""

# Calculate start time
START_TIME=$(date -u -v-${MINUTES}M +%s)000

# Function to format log output
format_logs() {
  jq -r '.events[] | "\(.timestamp | . / 1000 | strftime("%Y-%m-%d %H:%M:%S")) | \(.message)"' 2>/dev/null || \
  jq -r '.events[].message' 2>/dev/null || \
  cat
}

# Search logs using CloudWatch filter
if [ -z "$FILTER_PATTERN" ]; then
  echo "📄 Retrieving all logs..."
  aws logs filter-log-events \
    --log-group-name $LOG_GROUP \
    --start-time $START_TIME \
    --region $AWS_REGION \
    | format_logs
else
  echo "🔎 Searching for: $FILTER_PATTERN"
  aws logs filter-log-events \
    --log-group-name $LOG_GROUP \
    --start-time $START_TIME \
    --filter-pattern "$FILTER_PATTERN" \
    --region $AWS_REGION \
    | format_logs
fi

echo ""
echo "💡 Tips:"
echo "   - Use quotes for complex patterns: \"error AND campaign\""
echo "   - Use ? for any single character, * for zero or more characters"
echo "   - CloudWatch patterns are case-sensitive"
echo "   - Examples:"
echo "     ./aws/search-logs.sh 60 \"?campaign_viewer\""
echo "     ./aws/search-logs.sh 120 \"ERROR 500\""
echo "     ./aws/search-logs.sh 30 \"scout AND canvas\""
