#!/bin/bash
set -e

# Configuration
AWS_REGION=${AWS_REGION:-us-east-1}
PIPELINE_NAME="agent-marketing-pipeline"
GITHUB_OWNER="NuvolaNetworks"  # Update if different
GITHUB_REPO="agent_marketing"
GITHUB_BRANCH="prod"  # Deploy from prod branch

echo "🔄 Updating CodePipeline to use GitHub source..."

# Step 1: Create GitHub connection (if not exists)
echo "📡 Checking for existing GitHub connection..."
CONNECTION_ARN=$(aws codestar-connections list-connections --region $AWS_REGION \
  --query "Connections[?ConnectionName=='github-connection'].ConnectionArn" \
  --output text)

if [ -z "$CONNECTION_ARN" ]; then
  echo "Creating new GitHub connection..."
  CONNECTION_ARN=$(aws codestar-connections create-connection \
    --provider-type GitHub \
    --connection-name github-connection \
    --region $AWS_REGION \
    --query 'ConnectionArn' \
    --output text)
  
  echo "⚠️  IMPORTANT: You need to manually complete the GitHub OAuth flow!"
  echo "   Go to: https://console.aws.amazon.com/codesuite/settings/connections"
  echo "   Find: github-connection"
  echo "   Click: 'Update pending connection' and authorize with GitHub"
  echo ""
  read -p "Press ENTER after you've completed the OAuth authorization..."
else
  echo "✅ Using existing GitHub connection: $CONNECTION_ARN"
fi

# Step 2: Get current pipeline
echo "📥 Getting current pipeline configuration..."
aws codepipeline get-pipeline --name $PIPELINE_NAME --region $AWS_REGION > /tmp/pipeline-backup.json

# Step 3: Update pipeline with GitHub source
echo "📝 Updating pipeline to use GitHub..."
cat > /tmp/pipeline-update.json << EOF
{
  "pipeline": {
    "name": "$PIPELINE_NAME",
    "roleArn": "$(aws codepipeline get-pipeline --name $PIPELINE_NAME --region $AWS_REGION --query 'pipeline.roleArn' --output text)",
    "artifactStore": $(aws codepipeline get-pipeline --name $PIPELINE_NAME --region $AWS_REGION --query 'pipeline.artifactStore' --output json),
    "stages": [
      {
        "name": "Source",
        "actions": [
          {
            "name": "SourceAction",
            "actionTypeId": {
              "category": "Source",
              "owner": "AWS",
              "provider": "CodeStarSourceConnection",
              "version": "1"
            },
            "configuration": {
              "ConnectionArn": "$CONNECTION_ARN",
              "FullRepositoryId": "$GITHUB_OWNER/$GITHUB_REPO",
              "BranchName": "$GITHUB_BRANCH",
              "OutputArtifactFormat": "CODE_ZIP"
            },
            "outputArtifacts": [
              {
                "name": "SourceOutput"
              }
            ]
          }
        ]
      },
      $(aws codepipeline get-pipeline --name $PIPELINE_NAME --region $AWS_REGION --query 'pipeline.stages[1:]' --output json | jq -c '.')
    ]
  }
}
EOF

# Step 4: Update the pipeline
echo "🚀 Updating pipeline..."
aws codepipeline update-pipeline --cli-input-json file:///tmp/pipeline-update.json --region $AWS_REGION

echo "✅ Pipeline updated successfully!"
echo ""
echo "📋 Summary:"
echo "   - Source: GitHub ($GITHUB_OWNER/$GITHUB_REPO)"
echo "   - Branch: $GITHUB_BRANCH"
echo "   - Connection: $CONNECTION_ARN"
echo ""
echo "🎯 Next steps:"
echo "   1. Push to the 'prod' branch to trigger deployment"
echo "   2. Monitor: https://console.aws.amazon.com/codesuite/codepipeline/pipelines/$PIPELINE_NAME/view"




