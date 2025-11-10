#!/bin/bash
# Script to create Active Record encryption secrets in AWS Secrets Manager

set -e

AWS_REGION=${AWS_REGION:-us-east-1}

echo "🔐 Creating Active Record encryption secrets in AWS Secrets Manager..."
echo ""

# Generate secure keys
PRIMARY_KEY=$(openssl rand -hex 32)
DETERMINISTIC_KEY=$(openssl rand -hex 32)
SALT=$(openssl rand -hex 32)

echo "📝 Generated encryption keys:"
echo "  Primary key: ${PRIMARY_KEY:0:8}..."
echo "  Deterministic key: ${DETERMINISTIC_KEY:0:8}..."
echo "  Salt: ${SALT:0:8}..."
echo ""

# Create secrets in AWS
echo "📤 Creating secrets in AWS Secrets Manager..."

# Primary key
aws secretsmanager create-secret \
  --name "agent-marketing/active_record_encryption/primary_key" \
  --secret-string "$PRIMARY_KEY" \
  --region $AWS_REGION || echo "Primary key secret already exists"

# Deterministic key
aws secretsmanager create-secret \
  --name "agent-marketing/active_record_encryption/deterministic_key" \
  --secret-string "$DETERMINISTIC_KEY" \
  --region $AWS_REGION || echo "Deterministic key secret already exists"

# Salt
aws secretsmanager create-secret \
  --name "agent-marketing/active_record_encryption/key_derivation_salt" \
  --secret-string "$SALT" \
  --region $AWS_REGION || echo "Salt secret already exists"

echo ""
echo "✅ Secrets created successfully!"
echo ""
echo "📋 Add these to your ECS task definition environment variables:"
echo ""
echo "  ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY: <from secrets manager>"
echo "  ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY: <from secrets manager>" 
echo "  ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT: <from secrets manager>"
echo ""
echo "Or reference them directly in your task definition as secrets."
