# Dev Environment Setup Guide

## Overview

This guide explains how to set up and manage the dev environment for Agent Marketing on AWS.

## Architecture

The dev environment is a scaled-down version of production with:
- Smaller instance sizes (cost-optimized)
- Single AZ deployment (no Multi-AZ)
- No NAT gateways (uses public subnets to save costs)
- Optional SSL certificate
- Separate database and Redis instances
- Independent ECS cluster and services

## Prerequisites

1. AWS CLI configured with appropriate credentials
2. Terraform installed (v1.0+)
3. Docker installed (for building images)
4. Access to the GitHub repository

## Initial Setup

### 1. Initialize Terraform

```bash
cd aws/terraform
terraform init -backend-config=backend-dev.conf
terraform workspace select dev || terraform workspace new dev
```

### 2. Review Configuration

Check `environments/dev.tfvars` for:
- Instance sizes
- Domain settings
- Cost optimization flags

### 3. Deploy Infrastructure

```bash
# Plan first to review changes
terraform plan -var-file=environments/dev.tfvars

# Apply the configuration
terraform apply -var-file=environments/dev.tfvars
```

This will create:
- VPC with public/private subnets
- ECS cluster and service
- RDS PostgreSQL database
- ElastiCache Redis
- Application Load Balancer
- ECR repository
- Secrets Manager entries
- IAM roles and policies

### 4. Post-Deployment Setup

After Terraform completes:

```bash
# Run the post-setup script
./post-terraform-dev-setup.sh
```

This script will:
- Set the Rails master key
- Build and push the Docker image
- Create dev-specific task definitions
- Display connection information

## Accessing the Dev Environment

### Without SSL (Default)

Use the ALB DNS directly:
```
http://<alb-dns-name>.us-east-1.elb.amazonaws.com
```

### With SSL (Optional)

1. In GoDaddy, add a CNAME record:
   - Name: `dev`
   - Value: `<alb-dns-name>.us-east-1.elb.amazonaws.com`

2. Update `dev.tfvars`:
   ```hcl
   create_certificate = true
   ```

3. Re-run Terraform:
   ```bash
   terraform apply -var-file=environments/dev.tfvars
   ```

4. Wait for certificate validation (can take 30-45 minutes)

## Monitoring

### ECS Service Status
```bash
aws ecs describe-services \
  --cluster agent-marketing-dev-cluster \
  --services agent-marketing-dev
```

### View Logs
```bash
# Tail application logs
aws logs tail /ecs/agent-marketing-dev --follow

# View recent errors
aws logs filter-log-events \
  --log-group-name /ecs/agent-marketing-dev \
  --filter-pattern "ERROR"
```

### Database Connection
```bash
# Get database endpoint
terraform output database_endpoint

# Connect using psql
psql -h <endpoint> -U agent_marketing_dev -d agent_marketing_dev
```

## Deployment

### Manual Deployment

1. Build new image:
   ```bash
   docker build -f aws/Dockerfile -t agent-marketing-dev .
   ```

2. Push to ECR:
   ```bash
   aws ecr get-login-password | docker login --username AWS --password-stdin <ecr-url>
   docker tag agent-marketing-dev:latest <ecr-url>:latest
   docker push <ecr-url>:latest
   ```

3. Update ECS service:
   ```bash
   aws ecs update-service \
     --cluster agent-marketing-dev-cluster \
     --service agent-marketing-dev \
     --force-new-deployment
   ```

### Automated Deployment (CI/CD)

A separate CodePipeline can be set up to automatically deploy from the `dev` branch.

## Cost Management

The dev environment is optimized for cost:
- `db.t3.micro` for RDS (~$15/month)
- `cache.t3.micro` for Redis (~$13/month)
- Single ECS task (1 vCPU, 2GB RAM)
- No NAT gateways (saves ~$90/month)
- Reduced backup retention (1 day vs 7)

Estimated monthly cost: ~$150-200

## Maintenance

### Scaling
```bash
# Scale ECS service
aws ecs update-service \
  --cluster agent-marketing-dev-cluster \
  --service agent-marketing-dev \
  --desired-count 2
```

### Database Snapshots
```bash
# Create manual snapshot
aws rds create-db-snapshot \
  --db-instance-identifier agent-marketing-dev-db \
  --db-snapshot-identifier dev-manual-$(date +%Y%m%d)
```

### Destroy Environment
```bash
# When no longer needed
terraform destroy -var-file=environments/dev.tfvars
```

## Troubleshooting

### Service Not Starting
1. Check ECS task logs
2. Verify secrets are set correctly
3. Ensure Docker image was pushed
4. Check security group rules

### Database Connection Issues
1. Verify security group allows access
2. Check database is running
3. Confirm credentials in Secrets Manager

### SSL Certificate Issues
1. Verify DNS records are correct
2. Check certificate validation status
3. Ensure domain ownership

## Security Notes

- Dev uses the same secret structure as prod but with `-dev` suffix
- Database passwords are auto-generated and stored in Secrets Manager
- All traffic is encrypted in transit
- Public subnets are used for cost savings (no NAT)

## Contact

For issues or questions, contact the DevOps team or create an issue in the repository.
