#!/bin/bash

# Create Gemini API secrets for agent-marketing
# Run this script with your actual API key

set -e

REGION="us-east-1"

# Check if GEMINI_API_KEY is provided
if [ -z "$1" ]; then
  echo "Usage: ./create-gemini-secrets.sh <YOUR_GEMINI_API_KEY>"
  echo ""
  echo "Example:"
  echo "  ./create-gemini-secrets.sh AIzaSyABC123..."
  exit 1
fi

GEMINI_API_KEY="$1"
GEMINI_IMAGE_MODEL="imagen-3.0-generate-002"

echo "🔑 Creating Gemini secrets in AWS Secrets Manager..."
echo "   Region: $REGION"
echo ""

# Create GEMINI_API_KEY secret
echo "📝 Creating agent-marketing-gemini-api-key..."
aws secretsmanager create-secret \
  --name "agent-marketing-gemini-api-key" \
  --description "Gemini API key for image generation" \
  --secret-string "$GEMINI_API_KEY" \
  --region $REGION \
  2>/dev/null || \
aws secretsmanager update-secret \
  --secret-id "agent-marketing-gemini-api-key" \
  --secret-string "$GEMINI_API_KEY" \
  --region $REGION

echo "✅ Created/updated agent-marketing-gemini-api-key"

# Create GEMINI_IMAGE_MODEL secret
echo "📝 Creating agent-marketing-gemini-image-model..."
aws secretsmanager create-secret \
  --name "agent-marketing-gemini-image-model" \
  --description "Gemini image model name" \
  --secret-string "$GEMINI_IMAGE_MODEL" \
  --region $REGION \
  2>/dev/null || \
aws secretsmanager update-secret \
  --secret-id "agent-marketing-gemini-image-model" \
  --secret-string "$GEMINI_IMAGE_MODEL" \
  --region $REGION

echo "✅ Created/updated agent-marketing-gemini-image-model"

echo ""
echo "🎉 Done! Secrets created successfully."
echo ""
echo "📋 Next steps:"
echo "1. Get the secret ARNs:"
echo "   aws secretsmanager describe-secret --secret-id agent-marketing-gemini-api-key --region $REGION --query ARN --output text"
echo "   aws secretsmanager describe-secret --secret-id agent-marketing-gemini-image-model --region $REGION --query ARN --output text"
echo ""
echo "2. Add these to your task-definition.json in the 'secrets' array:"
echo '   {'
echo '     "name": "GEMINI_API_KEY",'
echo '     "valueFrom": "<ARN from step 1>"'
echo '   },'
echo '   {'
echo '     "name": "GEMINI_IMAGE_MODEL",'
echo '     "valueFrom": "<ARN from step 1>"'
echo '   }'
echo ""
echo "3. Re-deploy your ECS service"

