#!/bin/bash

# Setup SSL certificate for amoslabs.com domain
# This script applies Terraform configuration for the SSL certificate

set -e

DOMAIN="amoslabs.com"
AWS_REGION="us-east-1"

echo "🔐 Setting up SSL certificate for $DOMAIN..."

# Change to terraform directory
cd "$(dirname "$0")/terraform"

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    echo "📦 Initializing Terraform..."
    terraform init -backend-config=backend.conf
fi

# Plan and apply with the domain
echo "📋 Planning SSL certificate setup..."
terraform plan -var="domain_name=$DOMAIN" -target=aws_acm_certificate.main -target=aws_acm_certificate_validation.main

echo "🚀 Applying SSL certificate configuration..."
terraform apply -auto-approve -var="domain_name=$DOMAIN" -target=aws_acm_certificate.main -target=aws_acm_certificate_validation.main

echo "📋 Getting certificate validation DNS records..."
terraform output certificate_validation_records

echo ""
echo "✅ SSL certificate requested for $DOMAIN"
echo ""
echo "🔍 Next steps:"
echo "1. Add the DNS validation records shown above to your GoDaddy DNS"
echo "2. Wait for certificate validation (usually 5-30 minutes)"
echo "3. Apply the full infrastructure with the HTTPS listener:"
echo "   terraform apply -var=\"domain_name=$DOMAIN\""
echo ""
echo "4. Update your DNS to point to the ALB:"
terraform output alb_dns_name
echo ""
