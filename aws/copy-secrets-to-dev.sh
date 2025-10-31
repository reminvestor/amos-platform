#!/bin/bash
set -e

AWS_REGION="us-east-1"

echo "📦 Copying prod secrets to dev environment..."
echo ""

SECRETS=(
  "database-url"
  "redis-url"
  "rails-master-key"
  "mailgun-api-key"
  "mailgun-domain"
  "pinecone-api-key"
  "pinecone-environment"
  "pinecone-index-name"
  "openai-api-key"
  "anthropic-api-key"
  "deepgram-api-key"
  "deepgram-webhook-secret"
)

for secret in "${SECRETS[@]}"; do
  echo "  Copying ${secret}..."
  
  # Get value from prod secret
  PROD_VALUE=$(aws secretsmanager get-secret-value \
    --secret-id "agent-marketing-${secret}" \
    --query 'SecretString' \
    --output text \
    --region $AWS_REGION 2>/dev/null || echo "")
  
  if [ -n "$PROD_VALUE" ]; then
    # For database and redis, we'll update these after Terraform creates the resources
    if [[ "$secret" == "database-url" || "$secret" == "redis-url" ]]; then
      echo "    ⏭️  Skipping ${secret} (will be created by Terraform)"
      continue
    fi
    
    # Create dev secret with same value
    aws secretsmanager create-secret \
      --name "agent-marketing-dev-${secret}" \
      --secret-string "$PROD_VALUE" \
      --description "Dev environment - ${secret}" \
      --region $AWS_REGION 2>/dev/null && echo "    ✅ Created" || \
    aws secretsmanager update-secret \
      --secret-id "agent-marketing-dev-${secret}" \
      --secret-string "$PROD_VALUE" \
      --region $AWS_REGION && echo "    ✅ Updated"
  else
    echo "    ⚠️  Skipped (prod secret not found or empty)"
  fi
done

echo ""
echo "✅ Secrets copied to dev environment!"
echo ""
echo "Note: database-url and redis-url will be created by Terraform"

