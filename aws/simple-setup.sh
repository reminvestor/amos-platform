#!/bin/bash
set -e

echo "🔧 AWS Infrastructure Setup for Agent Marketing (Simple Version)"
echo "========================================================"

# Check prerequisites
command -v terraform >/dev/null 2>&1 || { echo "❌ Terraform is required but not installed. Please install terraform."; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "❌ AWS CLI is required but not installed. Please install aws-cli."; exit 1; }

# Get Rails master key
if [ -f "config/master.key" ]; then
    RAILS_MASTER_KEY=$(cat config/master.key)
    echo "✅ Found Rails master key"
else
    echo "❌ config/master.key not found. Please ensure it exists."
    exit 1
fi

cd aws/terraform

# Terraform is already initialized
echo "📦 Using existing Terraform configuration..."

echo "📋 Planning infrastructure..."
terraform plan

# Confirm deployment
read -p "Do you want to apply these changes? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Deployment cancelled"
    exit 0
fi

# Apply Terraform
echo "🚀 Creating infrastructure..."
terraform apply -auto-approve

# Get outputs
ECR_REPO=$(terraform output -raw ecr_repository_url)
ALB_DNS=$(terraform output -raw alb_dns_name)

# Store Rails master key in Secrets Manager
echo "🔐 Storing Rails master key in Secrets Manager..."
aws secretsmanager put-secret-value \
    --secret-id "agent-marketing-rails-master-key" \
    --secret-string "$RAILS_MASTER_KEY" \
    --region us-east-1 || echo "Secret already exists"

cd ../..

# Create .env.production file
cat > .env.production <<EOF
# AWS Configuration
AWS_REGION=us-east-1
AI_PROVIDER=bedrock

# Application
APPLICATION_HOST=$ALB_DNS
RAILS_LOG_TO_STDOUT=true

# These will be injected by ECS from Secrets Manager
# DATABASE_URL=(from Secrets Manager)
# RAILS_MASTER_KEY=(from Secrets Manager)
EOF

echo ""
echo "✅ Infrastructure setup complete!"
echo ""
echo "📝 Next steps:"
echo ""
echo "1. Deploy the application:"
echo "   ./aws/deploy.sh"
echo ""
echo "2. Run database migrations after deployment:"
echo "   ./aws/run-migration.sh"
echo ""
echo "3. Access your application at:"
echo "   http://$ALB_DNS"
echo ""
echo "ECR Repository: $ECR_REPO"
echo ""
echo "🔒 For production with HTTPS and custom domain:"
echo "   - Add an SSL certificate using AWS Certificate Manager"
echo "   - Create an HTTPS listener on the load balancer"
echo "   - Point your domain's DNS to: $ALB_DNS"
