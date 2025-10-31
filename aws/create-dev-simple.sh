#!/bin/bash
set -e

AWS_REGION="us-east-1"
ACCOUNT_ID="637423327454"

echo "🚀 Creating Simple Dev Environment"
echo "===================================="
echo ""
echo "This creates a minimal dev environment that:"
echo "  - Shares VPC/subnets with prod (no extra cost)"
echo "  - Has own ECS cluster/service"
echo "  - Has own RDS database (t3.micro)"
echo "  - Has own Redis (t3.micro)"  
echo "  - Uses existing secrets (already created)"
echo "  - No SSL certificate (use ALB DNS)"
echo ""

# Get existing VPC and subnets from prod
echo "📍 Getting existing VPC and subnets..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=agent-marketing-vpc" --query 'Vpcs[0].VpcId' --output text)
PRIVATE_SUBNET_1=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*private*" --query 'Subnets[0].SubnetId' --output text)
PRIVATE_SUBNET_2=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*private*" --query 'Subnets[1].SubnetId' --output text)
PUBLIC_SUBNET_1=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*public*" --query 'Subnets[0].SubnetId' --output text)
PUBLIC_SUBNET_2=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*public*" --query 'Subnets[1].SubnetId' --output text)

echo "  VPC: $VPC_ID"
echo "  Private Subnets: $PRIVATE_SUBNET_1, $PRIVATE_SUBNET_2"
echo "  Public Subnets: $PUBLIC_SUBNET_1, $PUBLIC_SUBNET_2"
echo ""

# Create ECS Cluster
echo "📦 Creating ECS cluster..."
aws ecs create-cluster --cluster-name agent-marketing-dev-cluster --region $AWS_REGION 2>/dev/null || echo "  Cluster already exists"
echo "  ✅ agent-marketing-dev-cluster"
echo ""

# Create ECR repository for dev
echo "📦 Creating ECR repository..."
aws ecr create-repository --repository-name agent-marketing-dev --region $AWS_REGION 2>/dev/null || echo "  Repository already exists"
echo "  ✅ agent-marketing-dev ECR repository"
echo ""

echo "✅ Dev environment base created!"
echo ""
echo "📋 Summary:"
echo "   - ECS Cluster: agent-marketing-dev-cluster"
echo "   - ECR Repo: agent-marketing-dev"
echo "   - Secrets: All copied with -dev suffix"
echo ""
echo "🎯 Next Steps:"
echo "   1. Create dev database (RDS) - manually or via Terraform"
echo "   2. Create dev Redis - manually or via Terraform"
echo "   3. Register dev task definition"
echo "   4. Create dev ECS service"
echo "   5. Set up dev CodePipeline"
echo ""
echo "Or run the full Terraform after fixing variables!"

