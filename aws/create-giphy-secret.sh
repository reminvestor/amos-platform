#!/bin/bash

# Create Giphy API Key Secret in AWS Secrets Manager
# Usage: ./create-giphy-secret.sh YOUR_GIPHY_API_KEY

set -e

GIPHY_API_KEY=$1
AWS_REGION="us-east-1"
AWS_ACCOUNT="637423327454"
SECRET_NAME="agent-marketing-giphy-api-key"

if [ -z "$GIPHY_API_KEY" ]; then
  echo "❌ Error: Please provide your Giphy API key as the first argument"
  echo "Usage: $0 YOUR_GIPHY_API_KEY"
  echo ""
  echo "Get a free API key at: https://developers.giphy.com/"
  exit 1
fi

echo "🔐 Creating Giphy API key secret in AWS Secrets Manager..."
echo "Secret name: $SECRET_NAME"
echo "Region: $AWS_REGION"

# Create the secret
aws secretsmanager create-secret \
  --name "$SECRET_NAME" \
  --description "Giphy API key for GIF search in Team Space" \
  --secret-string "$GIPHY_API_KEY" \
  --region "$AWS_REGION" \
  2>/dev/null || \
  aws secretsmanager update-secret \
    --secret-id "$SECRET_NAME" \
    --secret-string "$GIPHY_API_KEY" \
    --region "$AWS_REGION"

echo "✅ Secret created/updated successfully!"
echo ""
echo "📋 Secret ARN (use this in task definition):"
aws secretsmanager describe-secret \
  --secret-id "$SECRET_NAME" \
  --region "$AWS_REGION" \
  --query 'ARN' \
  --output text

echo ""
echo "✨ Next steps:"
echo "1. Add this to your task definition (aws/task-definition.json):"
echo ""
echo '        {'
echo '          "name": "GIPHY_API_KEY",'
echo '          "valueFrom": "arn:aws:secretsmanager:us-east-1:637423327454:secret:agent-marketing-giphy-api-key-XXXXXX"'
echo '        }'
echo ""
echo "2. Update the ECS service to use the new task definition"
echo "3. Restart the service for changes to take effect"

