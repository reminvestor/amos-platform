#!/bin/bash
set -e

# Configuration
AWS_REGION=${AWS_REGION:-us-east-1}
ENVIRONMENT="dev"
APP_NAME="agent-marketing-dev"

echo "🚀 Setting up Dev Environment for Agent Marketing"
echo "=================================================="
echo ""

# Step 1: Create dev secrets (copy from prod with -dev suffix)
echo "📦 Step 1: Creating dev secrets in AWS Secrets Manager..."
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
  echo "  Creating agent-marketing-dev-${secret}..."
  
  # Get value from prod secret
  PROD_VALUE=$(aws secretsmanager get-secret-value \
    --secret-id "agent-marketing-${secret}" \
    --query 'SecretString' \
    --output text \
    --region $AWS_REGION 2>/dev/null || echo "")
  
  if [ -n "$PROD_VALUE" ]; then
    # Create dev secret with same value (you can change later if needed)
    aws secretsmanager create-secret \
      --name "agent-marketing-dev-${secret}" \
      --secret-string "$PROD_VALUE" \
      --description "Dev environment secret for ${secret}" \
      --region $AWS_REGION 2>/dev/null || \
    aws secretsmanager update-secret \
      --secret-id "agent-marketing-dev-${secret}" \
      --secret-string "$PROD_VALUE" \
      --region $AWS_REGION
    
    echo "    ✅ agent-marketing-dev-${secret}"
  else
    echo "    ⚠️  Skipped (prod secret not found)"
  fi
done

echo ""
echo "✅ Dev secrets created!"
echo ""

# Step 2: Create dev task definition
echo "📝 Step 2: Creating dev task definition..."
echo ""

# Copy prod task definition and update for dev
cat aws/task-definition.json | jq '
  .family = "agent-marketing-dev" |
  .cpu = "1024" |
  .memory = "2048" |
  .containerDefinitions[0].name = "agent-marketing-dev" |
  .containerDefinitions[0].environment |= map(
    if .name == "RAILS_ENV" then .value = "development"
    elif .name == "RAILS_HOSTS" then .value = ".amazonaws.com,.elb.amazonaws.com,dev.amoslabs.com"
    else . end
  ) |
  .containerDefinitions[0].secrets |= map(
    .valueFrom |= gsub("agent-marketing-"; "agent-marketing-dev-")
  ) |
  .containerDefinitions[1].name = "solid-queue-worker-dev" |
  .containerDefinitions[1].environment |= map(
    if .name == "RAILS_ENV" then .value = "development"
    else . end
  ) |
  .containerDefinitions[1].secrets |= map(
    .valueFrom |= gsub("agent-marketing-"; "agent-marketing-dev-")
  )
' > aws/task-definition-dev.json

echo "✅ Dev task definition created at aws/task-definition-dev.json"
echo ""

# Step 3: Initialize Terraform for dev
echo "🏗️  Step 3: Initializing Terraform for dev environment..."
echo ""

cd aws/terraform

# Initialize Terraform
terraform init

# Create dev workspace
terraform workspace new dev 2>/dev/null || terraform workspace select dev

# Plan the infrastructure
echo "📋 Planning dev infrastructure..."
terraform plan -var-file=environments/dev.tfvars -out=dev.tfplan

echo ""
echo "⚠️  IMPORTANT: Review the plan above before applying!"
echo ""
read -p "Apply this Terraform plan? (yes/no): " APPLY

if [ "$APPLY" = "yes" ]; then
  echo "🚀 Applying Terraform plan..."
  terraform apply dev.tfplan
  echo ""
  echo "✅ Dev infrastructure created!"
else
  echo "❌ Skipping Terraform apply. Run manually with:"
  echo "   cd aws/terraform"
  echo "   terraform workspace select dev"
  echo "   terraform apply -var-file=environments/dev.tfvars"
  exit 0
fi

cd ../..

# Step 4: Create dev CodePipeline
echo ""
echo "🔄 Step 4: Creating dev CI/CD pipeline..."
echo ""

# Get the GitHub connection ARN
CONNECTION_ARN=$(aws codestar-connections list-connections --region $AWS_REGION \
  --query "Connections[?ConnectionName=='github-connection'].ConnectionArn" \
  --output text)

if [ -z "$CONNECTION_ARN" ]; then
  echo "❌ GitHub connection not found. Please run the prod setup first."
  exit 1
fi

# Create dev pipeline (similar to prod but for dev branch)
cat > /tmp/dev-pipeline.json << EOF
{
  "pipeline": {
    "name": "agent-marketing-dev-pipeline",
    "roleArn": "$(aws iam get-role --role-name agent-marketing-codepipeline-role --query 'Role.Arn' --output text)",
    "artifactStore": {
      "type": "S3",
      "location": "agent-marketing-codepipeline-artifacts-637423327454"
    },
    "stages": [
      {
        "name": "Source",
        "actions": [{
          "name": "Source",
          "actionTypeId": {
            "category": "Source",
            "owner": "AWS",
            "provider": "CodeStarSourceConnection",
            "version": "1"
          },
          "configuration": {
            "ConnectionArn": "$CONNECTION_ARN",
            "FullRepositoryId": "NuvolaNetworks/agent_marketing",
            "BranchName": "dev",
            "OutputArtifactFormat": "CODE_ZIP"
          },
          "outputArtifacts": [{"name": "source_output"}],
          "region": "$AWS_REGION",
          "runOrder": 1
        }]
      },
      {
        "name": "Build",
        "actions": [{
          "name": "Build",
          "actionTypeId": {
            "category": "Build",
            "owner": "AWS",
            "provider": "CodeBuild",
            "version": "1"
          },
          "configuration": {
            "ProjectName": "agent-marketing-dev-build"
          },
          "inputArtifacts": [{"name": "source_output"}],
          "outputArtifacts": [{"name": "build_output"}],
          "runOrder": 1
        }]
      },
      {
        "name": "Deploy",
        "actions": [{
          "name": "Deploy",
          "actionTypeId": {
            "category": "Deploy",
            "owner": "AWS",
            "provider": "ECS",
            "version": "1"
          },
          "configuration": {
            "ClusterName": "agent-marketing-dev-cluster",
            "ServiceName": "agent-marketing-dev",
            "FileName": "imagedefinitions.json"
          },
          "inputArtifacts": [{"name": "build_output"}],
          "runOrder": 1
        }]
      }
    ]
  }
}
EOF

# Create the pipeline
aws codepipeline create-pipeline \
  --cli-input-json file:///tmp/dev-pipeline.json \
  --region $AWS_REGION 2>/dev/null || \
  echo "Pipeline already exists, skipping creation"

echo ""
echo "✅ Dev environment setup complete!"
echo ""
echo "📋 Summary:"
echo "   - Environment: dev"
echo "   - Branch: dev"
echo "   - Cluster: agent-marketing-dev-cluster"
echo "   - Service: agent-marketing-dev"
echo "   - Pipeline: agent-marketing-dev-pipeline"
echo "   - Domain: dev.amoslabs.com (configure DNS)"
echo ""
echo "🎯 Next steps:"
echo "   1. Create 'dev' branch: git checkout -b dev && git push origin dev"
echo "   2. Configure DNS: Point dev.amoslabs.com to the dev ALB"
echo "   3. Push to dev branch to trigger automatic deployment"
echo ""
echo "💡 To deploy to dev:"
echo "   git push origin dev"
echo ""
echo "💡 To access dev logs:"
echo "   aws logs tail /ecs/agent-marketing-dev --follow"

