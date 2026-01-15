#!/bin/bash

# Script to grant ECS execution role access to Google OAuth secrets
# Usage: ./grant-google-oauth-secrets-access.sh

set -e

REGION="us-east-1"
ROLE_NAME="agent-marketing-ecs-execution-role"
POLICY_NAME="GoogleOAuthSecretsAccess"
ACCOUNT_ID="637423327454"

echo "🔐 Granting ECS execution role access to Google OAuth secrets..."
echo ""

# Create the inline policy document
POLICY_DOCUMENT=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue"
            ],
            "Resource": [
                "arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:agent-marketing-google-oauth-client-id-*",
                "arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:agent-marketing-google-oauth-client-secret-*"
            ]
        }
    ]
}
EOF
)

echo "📝 Adding inline policy to role: $ROLE_NAME"
echo ""

aws iam put-role-policy \
  --role-name $ROLE_NAME \
  --policy-name $POLICY_NAME \
  --policy-document "$POLICY_DOCUMENT"

echo "✅ Policy added successfully!"
echo ""
echo "Now redeploy the ECS service:"
echo "  aws ecs update-service --cluster agent-marketing --service agent-marketing-service --force-new-deployment --region $REGION"

