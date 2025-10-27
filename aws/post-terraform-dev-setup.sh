#!/bin/bash

# Post-Terraform setup script for dev environment
# Run this after Terraform apply completes

set -e

echo "🚀 Setting up dev environment post-Terraform..."

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Get outputs from Terraform
cd aws/terraform
ECR_URL=$(terraform output -raw ecr_repository_url 2>/dev/null || echo "")
ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "")

echo -e "${GREEN}✓ Terraform outputs retrieved${NC}"

# Set Rails master key if not already set
echo -e "\n${YELLOW}Setting Rails master key...${NC}"
if [ -f "../../config/master.key" ]; then
    aws secretsmanager put-secret-value \
        --secret-id "agent-marketing-dev-rails-master-key" \
        --secret-string "$(cat ../../config/master.key)" \
        --region us-east-1 2>/dev/null || echo "Rails master key already set"
    echo -e "${GREEN}✓ Rails master key configured${NC}"
else
    echo -e "${YELLOW}⚠️  config/master.key not found - please set manually${NC}"
fi

# Build and push initial Docker image
if [ -n "$ECR_URL" ]; then
    echo -e "\n${YELLOW}Building and pushing Docker image...${NC}"
    cd ../..
    
    # Login to ECR
    aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL
    
    # Build the image
    docker build -f aws/Dockerfile -t agent-marketing-dev .
    
    # Tag and push
    docker tag agent-marketing-dev:latest $ECR_URL:latest
    docker push $ECR_URL:latest
    
    echo -e "${GREEN}✓ Docker image pushed to ECR${NC}"
else
    echo -e "${YELLOW}⚠️  ECR URL not available yet - skipping Docker build${NC}"
fi

# Create dev-specific task definition
echo -e "\n${YELLOW}Creating dev task definition...${NC}"
cd aws
if [ -f "task-definition.json" ]; then
    # Copy and modify task definition for dev
    jq '.family = "agent-marketing-dev" | 
        .executionRoleArn = sub("agent-marketing"; "agent-marketing-dev") |
        .taskRoleArn = sub("agent-marketing"; "agent-marketing-dev") |
        .containerDefinitions[0].name = "agent-marketing-dev" |
        .containerDefinitions[0].image = "'$ECR_URL':latest" |
        .containerDefinitions[0].logConfiguration.options."awslogs-group" = "/ecs/agent-marketing-dev" |
        .containerDefinitions[0].environment = (.containerDefinitions[0].environment | map(
            if .name == "RAILS_ENV" then .value = "production"
            elif .name == "APP_DOMAIN" then .value = "dev.amoslabs.com"
            else . end
        )) |
        .containerDefinitions[0].secrets = (.containerDefinitions[0].secrets | map(
            .valueFrom = sub("agent-marketing-"; "agent-marketing-dev-")
        ))' task-definition.json > task-definition-dev.json
    
    echo -e "${GREEN}✓ Dev task definition created${NC}"
else
    echo -e "${YELLOW}⚠️  task-definition.json not found${NC}"
fi

# Display connection information
echo -e "\n${GREEN}🎉 Dev environment setup complete!${NC}"
echo -e "\n${YELLOW}Connection Information:${NC}"
if [ -n "$ALB_DNS" ]; then
    echo -e "ALB URL: http://$ALB_DNS"
    echo -e "\nTo access your dev environment:"
    echo -e "1. Wait ~5 minutes for ECS service to stabilize"
    echo -e "2. Visit: http://$ALB_DNS"
    echo -e "\nFor SSL (optional):"
    echo -e "1. Add CNAME record in GoDaddy: dev.amoslabs.com -> $ALB_DNS"
    echo -e "2. Re-run Terraform with create_certificate=true"
else
    echo -e "${YELLOW}⚠️  ALB DNS not available yet - Terraform may still be running${NC}"
fi

echo -e "\n${YELLOW}Next Steps:${NC}"
echo -e "1. Monitor ECS service: aws ecs describe-services --cluster agent-marketing-dev-cluster --services agent-marketing-dev"
echo -e "2. Check logs: aws logs tail /ecs/agent-marketing-dev --follow"
echo -e "3. Set up CodePipeline for continuous deployment (optional)"
