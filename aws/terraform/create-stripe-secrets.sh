#!/bin/bash

# Create Stripe secrets in AWS Secrets Manager
# Run this script BEFORE applying terraform changes

set -e

APP_NAME="agent-marketing"
REGION="us-east-1"

echo "Creating Stripe secrets for ${APP_NAME}..."
echo ""
echo "You'll need to get your Stripe keys from: https://dashboard.stripe.com/apikeys"
echo ""

# Prompt for keys
read -p "Enter your Stripe Secret Key (sk_live_... or sk_test_...): " STRIPE_SECRET_KEY
read -p "Enter your Stripe Publishable Key (pk_live_... or pk_test_...): " STRIPE_PUBLISHABLE_KEY
read -p "Enter your Stripe Webhook Secret (whsec_...): " STRIPE_WEBHOOK_SECRET

echo ""
echo "Creating secrets in AWS Secrets Manager..."

# Create or update secrets
aws secretsmanager create-secret \
  --name "${APP_NAME}-stripe-secret-key" \
  --secret-string "${STRIPE_SECRET_KEY}" \
  --region ${REGION} 2>/dev/null || \
aws secretsmanager put-secret-value \
  --secret-id "${APP_NAME}-stripe-secret-key" \
  --secret-string "${STRIPE_SECRET_KEY}" \
  --region ${REGION}

echo "✅ Created ${APP_NAME}-stripe-secret-key"

aws secretsmanager create-secret \
  --name "${APP_NAME}-stripe-publishable-key" \
  --secret-string "${STRIPE_PUBLISHABLE_KEY}" \
  --region ${REGION} 2>/dev/null || \
aws secretsmanager put-secret-value \
  --secret-id "${APP_NAME}-stripe-publishable-key" \
  --secret-string "${STRIPE_PUBLISHABLE_KEY}" \
  --region ${REGION}

echo "✅ Created ${APP_NAME}-stripe-publishable-key"

aws secretsmanager create-secret \
  --name "${APP_NAME}-stripe-webhook-secret" \
  --secret-string "${STRIPE_WEBHOOK_SECRET}" \
  --region ${REGION} 2>/dev/null || \
aws secretsmanager put-secret-value \
  --secret-id "${APP_NAME}-stripe-webhook-secret" \
  --secret-string "${STRIPE_WEBHOOK_SECRET}" \
  --region ${REGION}

echo "✅ Created ${APP_NAME}-stripe-webhook-secret"

echo ""
echo "🎉 All Stripe secrets created successfully!"
echo ""
echo "Next steps:"
echo "1. Run 'terraform plan' to see the changes"
echo "2. Run 'terraform apply' to deploy"
echo "3. Set up a webhook in Stripe Dashboard pointing to:"
echo "   https://app.amoslabs.com/stripe/webhooks"

