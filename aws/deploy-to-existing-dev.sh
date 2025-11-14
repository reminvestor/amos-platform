#!/bin/bash

# Quick deployment script for existing dev infrastructure
set -e

echo "🚀 Deploying to existing dev environment..."

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# Get ECR URL
ECR_URL="637423327454.dkr.ecr.us-east-1.amazonaws.com/agent-marketing-dev"
echo -e "${YELLOW}Using ECR URL: $ECR_URL${NC}"

# 1. Check/Update Rails master key
echo -e "\n${YELLOW}1. Ensuring Rails master key is set...${NC}"
if [ -f "config/master.key" ]; then
    aws secretsmanager put-secret-value \
        --secret-id "agent-marketing-dev-rails-master-key" \
        --secret-string "$(cat config/master.key)" \
        --region us-east-1 2>/dev/null && echo -e "${GREEN}✓ Rails master key updated${NC}" || echo -e "${YELLOW}Rails master key already set${NC}"
else
    echo -e "${RED}⚠️  config/master.key not found!${NC}"
    exit 1
fi

# 2. Build Docker image
echo -e "\n${YELLOW}2. Building Docker image...${NC}"
docker build -f aws/Dockerfile -t agent-marketing-dev . || {
    echo -e "${RED}Docker build failed!${NC}"
    exit 1
}
echo -e "${GREEN}✓ Docker image built${NC}"

# 3. Login to ECR
echo -e "\n${YELLOW}3. Logging into ECR...${NC}"
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL || {
    echo -e "${RED}ECR login failed!${NC}"
    exit 1
}
echo -e "${GREEN}✓ Logged into ECR${NC}"

# 4. Tag and push image
echo -e "\n${YELLOW}4. Pushing Docker image to ECR...${NC}"
docker tag agent-marketing-dev:latest $ECR_URL:latest
docker push $ECR_URL:latest || {
    echo -e "${RED}Docker push failed!${NC}"
    exit 1
}
echo -e "${GREEN}✓ Image pushed to ECR${NC}"

# 5. Create/Update task definition
echo -e "\n${YELLOW}5. Creating task definition...${NC}"
cat > aws/task-definition-dev.json << 'EOF'
{
  "family": "agent-marketing-dev",
  "executionRoleArn": "arn:aws:iam::637423327454:role/agent-marketing-dev-ecs-execution-role",
  "taskRoleArn": "arn:aws:iam::637423327454:role/agent-marketing-dev-ecs-task-role",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024",
  "memory": "2048",
  "containerDefinitions": [
    {
      "name": "agent-marketing-dev",
      "image": "637423327454.dkr.ecr.us-east-1.amazonaws.com/agent-marketing-dev:latest",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 3000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {"name": "RAILS_ENV", "value": "production"},
        {"name": "RAILS_LOG_TO_STDOUT", "value": "true"},
        {"name": "PORT", "value": "3000"},
        {"name": "APP_DOMAIN", "value": "dev.amoslabs.com"},
        {"name": "AWS_REGION", "value": "us-east-1"}
      ],
      "secrets": [
        {"name": "DATABASE_URL", "valueFrom": "arn:aws:secretsmanager:us-east-1:637423327454:secret:agent-marketing-dev-database-url"},
        {"name": "RAILS_MASTER_KEY", "valueFrom": "arn:aws:secretsmanager:us-east-1:637423327454:secret:agent-marketing-dev-rails-master-key"},
        {"name": "REDIS_URL", "valueFrom": "arn:aws:secretsmanager:us-east-1:637423327454:secret:agent-marketing-dev-redis-url"},
        {"name": "MAILGUN_API_KEY", "valueFrom": "arn:aws:secretsmanager:us-east-1:637423327454:secret:agent-marketing-dev-mailgun-api-key"},
        {"name": "MAILGUN_DOMAIN", "valueFrom": "arn:aws:secretsmanager:us-east-1:637423327454:secret:agent-marketing-dev-mailgun-domain"},
        {"name": "PINECONE_API_KEY", "valueFrom": "arn:aws:secretsmanager:us-east-1:637423327454:secret:agent-marketing-dev-pinecone-api-key"},
        {"name": "PINECONE_ENVIRONMENT", "valueFrom": "arn:aws:secretsmanager:us-east-1:637423327454:secret:agent-marketing-dev-pinecone-environment"},
        {"name": "PINECONE_INDEX_NAME", "valueFrom": "arn:aws:secretsmanager:us-east-1:637423327454:secret:agent-marketing-dev-pinecone-index-name"},
        {"name": "OPENAI_API_KEY", "valueFrom": "arn:aws:secretsmanager:us-east-1:637423327454:secret:agent-marketing-dev-openai-api-key"},
        {"name": "ANTHROPIC_API_KEY", "valueFrom": "arn:aws:secretsmanager:us-east-1:637423327454:secret:agent-marketing-dev-anthropic-api-key"},
        {"name": "DEEPGRAM_API_KEY", "valueFrom": "arn:aws:secretsmanager:us-east-1:637423327454:secret:agent-marketing-dev-deepgram-api-key"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/agent-marketing-dev",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
EOF

# Register task definition
aws ecs register-task-definition --cli-input-json file://aws/task-definition-dev.json --region us-east-1 > /dev/null
echo -e "${GREEN}✓ Task definition registered${NC}"

# 6. Create log group if it doesn't exist
echo -e "\n${YELLOW}6. Creating CloudWatch log group...${NC}"
aws logs create-log-group --log-group-name /ecs/agent-marketing-dev --region us-east-1 2>/dev/null && \
    echo -e "${GREEN}✓ Log group created${NC}" || echo -e "${YELLOW}Log group already exists${NC}"

# 7. Check if service exists, create if not
echo -e "\n${YELLOW}7. Checking ECS service...${NC}"
SERVICE_EXISTS=$(aws ecs describe-services --cluster agent-marketing-dev-cluster --services agent-marketing-dev --query 'services[0].status' --output text 2>/dev/null || echo "NONE")

if [ "$SERVICE_EXISTS" == "NONE" ] || [ "$SERVICE_EXISTS" == "INACTIVE" ]; then
    echo -e "${YELLOW}Creating new ECS service...${NC}"
    
    # Get subnet and security group info
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=agent-marketing-dev-vpc" --query 'Vpcs[0].VpcId' --output text)
    SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*private*" --query 'Subnets[*].SubnetId' --output text | tr '\t' ',')
    
    # Get ALB target group
    TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups --names agent-marketing-dev-tg --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")
    
    if [ -z "$TARGET_GROUP_ARN" ]; then
        echo -e "${YELLOW}Creating target group...${NC}"
        TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
            --name agent-marketing-dev-tg \
            --protocol HTTP \
            --port 3000 \
            --vpc-id $VPC_ID \
            --target-type ip \
            --health-check-path /health \
            --query 'TargetGroups[0].TargetGroupArn' \
            --output text)
    fi
    
    # Get or create security group
    SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=agent-marketing-dev-ecs-tasks" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
    
    if [ -z "$SG_ID" ] || [ "$SG_ID" == "None" ]; then
        echo -e "${YELLOW}Creating security group...${NC}"
        SG_ID=$(aws ec2 create-security-group \
            --group-name agent-marketing-dev-ecs-tasks \
            --description "Security group for dev ECS tasks" \
            --vpc-id $VPC_ID \
            --query 'GroupId' \
            --output text)
        
        # Allow inbound from ALB
        aws ec2 authorize-security-group-ingress \
            --group-id $SG_ID \
            --protocol tcp \
            --port 3000 \
            --source-group $(aws ec2 describe-security-groups --filters "Name=group-name,Values=agent-marketing-dev-alb" --query 'SecurityGroups[0].GroupId' --output text)
    fi
    
    # Create service
    aws ecs create-service \
        --cluster agent-marketing-dev-cluster \
        --service-name agent-marketing-dev \
        --task-definition agent-marketing-dev:latest \
        --desired-count 1 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
        --load-balancers "targetGroupArn=$TARGET_GROUP_ARN,containerName=agent-marketing-dev,containerPort=3000" \
        --health-check-grace-period-seconds 300 > /dev/null
    
    echo -e "${GREEN}✓ ECS service created${NC}"
else
    echo -e "${YELLOW}Updating existing ECS service...${NC}"
    aws ecs update-service \
        --cluster agent-marketing-dev-cluster \
        --service agent-marketing-dev \
        --task-definition agent-marketing-dev:latest \
        --force-new-deployment > /dev/null
    echo -e "${GREEN}✓ ECS service updated${NC}"
fi

# 8. Wait for deployment
echo -e "\n${YELLOW}8. Waiting for deployment to stabilize...${NC}"
echo -e "${YELLOW}This may take 3-5 minutes...${NC}"
aws ecs wait services-stable --cluster agent-marketing-dev-cluster --services agent-marketing-dev

echo -e "\n${GREEN}🎉 Deployment complete!${NC}"
echo -e "\n${YELLOW}Access your dev environment at:${NC}"
echo -e "  http://agent-marketing-dev-alb-1572082392.us-east-1.elb.amazonaws.com"
echo -e "  http://dev.amoslabs.com (once DNS propagates)"
echo -e "\n${YELLOW}View logs:${NC}"
echo -e "  aws logs tail /ecs/agent-marketing-dev --follow"



