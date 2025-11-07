#!/bin/bash
# Fix S3 permissions for agent-marketing-dev ECS task role

set -e

ROLE_NAME="agent-marketing-dev-ecs-task-role"
POLICY_NAME="agent-marketing-dev-ecs-task-s3"

echo "🔧 Updating IAM policy for dev environment..."
echo "Role: $ROLE_NAME"
echo "Policy: $POLICY_NAME"

# Get current policy to preserve storage bucket ARN
echo ""
echo "📋 Fetching existing policy..."

# Create updated policy with both buckets
POLICY_DOCUMENT=$(cat <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::agent-marketing-dev-storage-637423327454",
        "arn:aws:s3:::agent-marketing-dev-storage-637423327454/*",
        "arn:aws:s3:::agent-marketing-dev-rag-storage-637423327454",
        "arn:aws:s3:::agent-marketing-dev-rag-storage-637423327454/*",
        "arn:aws:s3:::agent-marketing-rag-storage",
        "arn:aws:s3:::agent-marketing-rag-storage/*"
      ]
    }
  ]
}
EOF
)

echo ""
echo "📝 Updating policy..."
aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "$POLICY_NAME" \
  --policy-document "$POLICY_DOCUMENT"

echo ""
echo "✅ Policy updated successfully!"
echo ""
echo "The dev ECS tasks can now upload to:"
echo "  - agent-marketing-dev-storage-637423327454 (Active Storage)"
echo "  - agent-marketing-dev-rag-storage-637423327454 (RAG Storage)"
echo "  - agent-marketing-rag-storage (legacy/shared bucket)"
echo ""
echo "🔄 You may need to redeploy or restart ECS tasks for the changes to take effect."

