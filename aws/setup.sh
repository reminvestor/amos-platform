#!/bin/bash
set -e

echo "🔧 AWS Infrastructure Setup for Agent Marketing"
echo "============================================="

# Check prerequisites
command -v terraform >/dev/null 2>&1 || { echo "❌ Terraform is required but not installed. Please install terraform."; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "❌ AWS CLI is required but not installed. Please install aws-cli."; exit 1; }

# Get domain name
read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME
if [ -z "$DOMAIN_NAME" ]; then
    echo "❌ Domain name is required"
    exit 1
fi

# Check if Route53 zone exists
echo "🔍 Checking for existing Route53 zone..."
ZONE_EXISTS=$(aws route53 list-hosted-zones-by-name --query "HostedZones[?Name=='${DOMAIN_NAME}.'].Id" --output text 2>/dev/null)

if [ -n "$ZONE_EXISTS" ]; then
    echo "✅ Found existing Route53 zone for $DOMAIN_NAME"
    CREATE_ROUTE53="false"
else
    echo "⚠️  No Route53 zone found for $DOMAIN_NAME"
    read -p "Do you want to create a Route53 hosted zone? (yes/no): " CREATE_ZONE
    if [ "$CREATE_ZONE" = "yes" ]; then
        CREATE_ROUTE53="true"
        echo "📝 Route53 zone will be created"
    else
        CREATE_ROUTE53="false"
        echo "📝 You'll need to manually configure DNS records with your provider"
    fi
fi

# Get Rails master key
if [ -f "config/master.key" ]; then
    RAILS_MASTER_KEY=$(cat config/master.key)
    echo "✅ Found Rails master key"
else
    echo "❌ config/master.key not found. Please ensure it exists."
    exit 1
fi

cd aws/terraform

# Initialize Terraform
echo "📦 Initializing Terraform..."
terraform init

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
domain_name = "$DOMAIN_NAME"
aws_region  = "us-east-1"
create_route53_zone = $CREATE_ROUTE53
EOF

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
APPLICATION_HOST=$DOMAIN_NAME
RAILS_LOG_TO_STDOUT=true

# These will be injected by ECS from Secrets Manager
# DATABASE_URL=(from Secrets Manager)
# RAILS_MASTER_KEY=(from Secrets Manager)
EOF

echo "✅ Infrastructure setup complete!"
echo ""
echo "📝 Next steps:"

if [ "$CREATE_ROUTE53" = "true" ]; then
    # Get nameservers
    NAMESERVERS=$(terraform output -json nameservers | jq -r '.[]')
    echo "1. Update your domain registrar to use these AWS nameservers:"
    for ns in $NAMESERVERS; do
        echo "   - $ns"
    done
else
    echo "1. Certificate Validation - Add these DNS records to your DNS provider:"
    terraform output -json certificate_validation_options | jq -r 'to_entries[] | "   \(.value.type) record: \(.value.name) → \(.value.value)"'
    echo ""
    echo "2. After certificate is validated, add these DNS records:"
    echo "   - CNAME: $DOMAIN_NAME → $ALB_DNS"
    echo "   - CNAME: www.$DOMAIN_NAME → $ALB_DNS"
    echo "   - CNAME: app.$DOMAIN_NAME → $ALB_DNS"
fi

echo ""
echo "2. Wait for DNS propagation (can take up to 48 hours)"
echo ""
echo "3. Run database migrations:"
echo "   aws/run-migration.sh"
echo ""
echo "4. Deploy the application:"
echo "   aws/deploy.sh"
echo ""
echo "ECR Repository: $ECR_REPO"
echo "Load Balancer: https://$ALB_DNS"
