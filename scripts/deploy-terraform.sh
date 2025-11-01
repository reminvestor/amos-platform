#!/bin/bash
# scripts/deploy-terraform.sh
# Deployment script for AWS Bedrock infrastructure

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ ${NC}$1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if environment argument is provided
if [ $# -eq 0 ]; then
    print_error "Usage: $0 <environment>"
    print_info "Available environments: dev, staging, production"
    exit 1
fi

ENVIRONMENT=$1
TERRAFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/terraform"
TFVARS_FILE="${TERRAFORM_DIR}/environments/${ENVIRONMENT}.tfvars"

# Validate environment
if [ ! -f "$TFVARS_FILE" ]; then
    print_error "Environment configuration not found: ${TFVARS_FILE}"
    exit 1
fi

print_info "Deploying to ${ENVIRONMENT} environment"
echo ""

# Check prerequisites
print_info "Checking prerequisites..."

if ! command -v terraform &> /dev/null; then
    print_error "Terraform is not installed"
    exit 1
fi
print_success "Terraform installed"

if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed"
    exit 1
fi
print_success "AWS CLI installed"

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured"
    exit 1
fi
print_success "AWS credentials configured"

AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region || echo "us-east-1")
print_info "AWS Account: ${AWS_ACCOUNT}"
print_info "AWS Region: ${AWS_REGION}"
echo ""

# Change to Terraform directory
cd "$TERRAFORM_DIR"

# Initialize Terraform
print_info "Initializing Terraform..."
terraform init -upgrade
print_success "Terraform initialized"
echo ""

# Validate configuration
print_info "Validating Terraform configuration..."
terraform validate
print_success "Configuration valid"
echo ""

# Format check
print_info "Checking Terraform formatting..."
if ! terraform fmt -check -recursive; then
    print_warning "Terraform files need formatting. Run: terraform fmt -recursive"
fi
echo ""

# Plan
print_info "Creating Terraform plan..."
terraform plan -var-file="$TFVARS_FILE" -out=tfplan
print_success "Plan created"
echo ""

# Show plan summary
print_info "Plan Summary:"
terraform show -json tfplan | jq -r '
  .resource_changes[] |
  "\(.change.actions[0]): \(.type).\(.name)"
' | sort | uniq -c

echo ""
print_warning "Review the plan above carefully!"
echo ""

# Confirm before apply
if [ "$ENVIRONMENT" = "production" ]; then
    print_warning "This is a PRODUCTION deployment!"
    read -p "Type 'DEPLOY' to continue: " -r
    if [ "$REPLY" != "DEPLOY" ]; then
        print_error "Deployment cancelled"
        exit 1
    fi
else
    read -p "Continue with deployment? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        print_error "Deployment cancelled"
        exit 1
    fi
fi

# Apply
print_info "Applying Terraform changes..."
terraform apply tfplan
print_success "Deployment complete!"
echo ""

# Clean up plan file
rm -f tfplan

# Output important values
print_info "Infrastructure outputs:"
terraform output -json | jq -r 'to_entries[] | "\(.key): \(.value.value)"'
echo ""

# Save outputs to file
OUTPUT_FILE="${TERRAFORM_DIR}/../config/terraform-outputs-${ENVIRONMENT}.json"
print_info "Saving outputs to ${OUTPUT_FILE}"
terraform output -json > "$OUTPUT_FILE"

print_success "Deployment to ${ENVIRONMENT} completed successfully!"
echo ""

# Display next steps
print_info "Next steps:"
echo "  1. Update .env file with new values:"
echo "     - BEDROCK_KB_ID=$(terraform output -raw bedrock_knowledge_base_id 2>/dev/null || echo 'N/A')"
echo "     - RAG_BUCKET=$(terraform output -raw s3_rag_bucket_name 2>/dev/null || echo 'N/A')"
echo ""
echo "  2. Run database migrations:"
echo "     rails db:migrate"
echo ""
echo "  3. Test the infrastructure:"
echo "     ./scripts/test-infrastructure.sh ${ENVIRONMENT}"
echo ""

print_success "All done! 🎉"