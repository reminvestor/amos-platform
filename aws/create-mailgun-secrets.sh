#!/bin/bash

# Script to create Mailgun secrets in AWS Secrets Manager
# Run this once to set up the secrets, then Terraform and CodePipeline will handle the rest

set -e

# Configuration
AWS_REGION="us-east-1"
SECRET_PREFIX="agent-marketing"

echo "🔐 Setting up Mailgun configuration for CodePipeline deployment..."
echo ""

# Check if .env file exists
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found!"
    echo "Please ensure your .env file contains MAILGUN_API_KEY and MAILGUN_DOMAIN"
    exit 1
fi

# Load environment variables from .env
source .env

# Verify required variables are set
if [ -z "$MAILGUN_API_KEY" ] || [ -z "$MAILGUN_DOMAIN" ]; then
    echo "❌ Error: MAILGUN_API_KEY or MAILGUN_DOMAIN not found in .env file!"
    exit 1
fi

echo "📧 Creating Mailgun secrets in AWS Secrets Manager..."

# Create MAILGUN_API_KEY secret
echo "Creating MAILGUN_API_KEY secret..."
aws secretsmanager create-secret \
  --name "${SECRET_PREFIX}-mailgun-api-key" \
  --description "Mailgun API key for agent-marketing" \
  --secret-string "$MAILGUN_API_KEY" \
  --region $AWS_REGION 2>/dev/null || \
aws secretsmanager update-secret \
  --secret-id "${SECRET_PREFIX}-mailgun-api-key" \
  --secret-string "$MAILGUN_API_KEY" \
  --region $AWS_REGION

# Create MAILGUN_DOMAIN secret
echo "Creating MAILGUN_DOMAIN secret..."
aws secretsmanager create-secret \
  --name "${SECRET_PREFIX}-mailgun-domain" \
  --description "Mailgun domain for agent-marketing" \
  --secret-string "$MAILGUN_DOMAIN" \
  --region $AWS_REGION 2>/dev/null || \
aws secretsmanager update-secret \
  --secret-id "${SECRET_PREFIX}-mailgun-domain" \
  --secret-string "$MAILGUN_DOMAIN" \
  --region $AWS_REGION

echo ""
echo "✅ Mailgun secrets created/updated successfully!"
echo ""
echo "📋 Next steps:"
echo "1. Run: cd aws/terraform && terraform apply"
echo "2. Commit your changes: git add . && git commit -m 'Add Mailgun configuration'"
echo "3. Deploy via CodePipeline: ./aws/deploy-pipeline.sh"
echo ""
echo "The ECS task will now have access to:"
echo "  - MAILGUN_API_KEY (from Secrets Manager)"
echo "  - MAILGUN_DOMAIN (from Secrets Manager)"
