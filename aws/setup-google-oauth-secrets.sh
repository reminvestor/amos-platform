#!/bin/bash

# Script to create Google OAuth secrets in AWS Secrets Manager
# Usage: ./setup-google-oauth-secrets.sh

set -e

REGION="us-east-1"
SECRET_PREFIX="agent-marketing"

echo "🔐 Setting up Google OAuth secrets in AWS Secrets Manager..."
echo "Region: $REGION"
echo ""

# Check if secrets already exist
echo "Checking for existing secrets..."

CLIENT_ID_EXISTS=$(aws secretsmanager describe-secret \
  --secret-id "${SECRET_PREFIX}-google-oauth-client-id" \
  --region $REGION 2>/dev/null && echo "true" || echo "false")

CLIENT_SECRET_EXISTS=$(aws secretsmanager describe-secret \
  --secret-id "${SECRET_PREFIX}-google-oauth-client-secret" \
  --region $REGION 2>/dev/null && echo "true" || echo "false")

# Prompt for values
echo ""
read -p "Enter Google OAuth Client ID: " GOOGLE_CLIENT_ID
read -sp "Enter Google OAuth Client Secret: " GOOGLE_CLIENT_SECRET
echo ""

if [ -z "$GOOGLE_CLIENT_ID" ] || [ -z "$GOOGLE_CLIENT_SECRET" ]; then
  echo "❌ Error: Both Client ID and Client Secret are required"
  exit 1
fi

# Create or update Client ID secret
echo ""
echo "📝 Setting up GOOGLE_OAUTH_CLIENT_ID..."
if [ "$CLIENT_ID_EXISTS" = "true" ]; then
  aws secretsmanager put-secret-value \
    --secret-id "${SECRET_PREFIX}-google-oauth-client-id" \
    --secret-string "$GOOGLE_CLIENT_ID" \
    --region $REGION
  echo "   ✅ Updated existing secret"
else
  aws secretsmanager create-secret \
    --name "${SECRET_PREFIX}-google-oauth-client-id" \
    --description "Google OAuth Client ID for AMOS" \
    --secret-string "$GOOGLE_CLIENT_ID" \
    --region $REGION
  echo "   ✅ Created new secret"
fi

# Create or update Client Secret
echo ""
echo "📝 Setting up GOOGLE_OAUTH_CLIENT_SECRET..."
if [ "$CLIENT_SECRET_EXISTS" = "true" ]; then
  aws secretsmanager put-secret-value \
    --secret-id "${SECRET_PREFIX}-google-oauth-client-secret" \
    --secret-string "$GOOGLE_CLIENT_SECRET" \
    --region $REGION
  echo "   ✅ Updated existing secret"
else
  aws secretsmanager create-secret \
    --name "${SECRET_PREFIX}-google-oauth-client-secret" \
    --description "Google OAuth Client Secret for AMOS" \
    --secret-string "$GOOGLE_CLIENT_SECRET" \
    --region $REGION
  echo "   ✅ Created new secret"
fi

# Get the ARNs
echo ""
echo "📋 Fetching secret ARNs..."
CLIENT_ID_ARN=$(aws secretsmanager describe-secret \
  --secret-id "${SECRET_PREFIX}-google-oauth-client-id" \
  --region $REGION \
  --query 'ARN' --output text)

CLIENT_SECRET_ARN=$(aws secretsmanager describe-secret \
  --secret-id "${SECRET_PREFIX}-google-oauth-client-secret" \
  --region $REGION \
  --query 'ARN' --output text)

echo ""
echo "=========================================="
echo "✅ Google OAuth secrets created successfully!"
echo "=========================================="
echo ""
echo "Add these to your task-definition.json secrets array:"
echo ""
echo "{"
echo '  "name": "GOOGLE_OAUTH_CLIENT_ID",'
echo '  "valueFrom": "'$CLIENT_ID_ARN'"'
echo "},"
echo "{"
echo '  "name": "GOOGLE_OAUTH_CLIENT_SECRET",'
echo '  "valueFrom": "'$CLIENT_SECRET_ARN'"'
echo "}"
echo ""
echo "=========================================="
echo "Secret ARNs for reference:"
echo "=========================================="
echo "CLIENT_ID:     $CLIENT_ID_ARN"
echo "CLIENT_SECRET: $CLIENT_SECRET_ARN"
echo ""
echo "After updating task-definition.json, deploy with:"
echo "  aws ecs update-service --cluster agent-marketing --service agent-marketing-service --force-new-deployment --region $REGION"

