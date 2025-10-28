#!/bin/bash
set -e

AWS_REGION="us-east-1"
echo "🚀 Deploying Dev Environment"
echo "=============================="
echo ""

# Step 1: Copy prod secrets to dev
echo "📦 Step 1/4: Setting up dev secrets..."
./aws/copy-secrets-to-dev.sh

# Step 2: Create dev branch if it doesn't exist
echo ""
echo "🌿 Step 2/4: Setting up dev branch..."
git checkout -b dev 2>/dev/null || git checkout dev
git push origin dev 2>/dev/null || echo "Dev branch already exists on remote"

# Step 3: Apply Terraform for dev environment
echo ""
echo "🏗️  Step 3/4: Creating dev infrastructure with Terraform..."
cd aws/terraform

terraform init
terraform workspace new dev 2>/dev/null || terraform workspace select dev

echo "Planning infrastructure..."
terraform apply -var-file=environments/dev.tfvars -auto-approve

cd ../..

echo ""
echo "✅ Dev environment created!"
echo ""
echo "📋 Next Steps:"
echo "   1. Wait ~5 minutes for services to stabilize"
echo "   2. Get ALB URL: aws elbv2 describe-load-balancers --query \"LoadBalancers[?contains(LoadBalancerName, 'dev')].DNSName\" --output text"
echo "   3. Configure DNS: Point dev.amoslabs.com to the ALB"  
echo "   4. Push to dev branch to deploy: git push origin dev"
echo ""
echo "🔗 Useful commands:"
echo "   - View logs: aws logs tail /ecs/agent-marketing-dev --follow"
echo "   - Check service: aws ecs describe-services --cluster agent-marketing-dev-cluster --services agent-marketing-dev"
echo "   - Run migrations: aws ecs execute-command --cluster agent-marketing-dev-cluster --task TASK_ID --container agent-marketing-dev --interactive --command '/bin/bash'"

