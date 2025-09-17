# AWS Migration Guide

This guide documents the migration from Heroku to AWS using ECS Fargate and Bedrock for AI services.

## Architecture Overview

- **Compute**: ECS Fargate (containerized Rails app)
- **Database**: RDS PostgreSQL
- **Storage**: S3 for Active Storage
- **AI Services**: AWS Bedrock (Claude and Titan models)
- **Load Balancer**: Application Load Balancer with SSL
- **DNS**: Route53
- **Secrets**: AWS Secrets Manager
- **Container Registry**: ECR

## Migration Steps

### 1. Prerequisites

- AWS CLI configured with credentials
- Terraform installed
- Docker installed
- Domain name ready for migration

### 2. Initial Setup

```bash
# Install AWS SDK dependencies
bundle add aws-sdk-bedrockruntime aws-sdk-s3
bundle install

# Run the setup script
./aws/setup.sh
```

This will:
- Create all AWS infrastructure using Terraform
- Set up VPC, RDS, S3, ECS cluster, etc.
- Configure SSL certificates
- Store secrets in AWS Secrets Manager

### 3. Database Migration

```bash
# Export data from Heroku
heroku pg:backups:capture --app your-heroku-app
heroku pg:backups:download --app your-heroku-app

# Import to RDS (after infrastructure is created)
# Get RDS endpoint from Terraform output
# Use pg_restore to import the data
```

### 4. Deploy Application

```bash
# Build and deploy
./aws/deploy.sh
```

This will:
- Build Docker image
- Push to ECR
- Update ECS service
- Run with zero downtime

### 5. Run Migrations

```bash
# Run database migrations on ECS
./aws/run-migration.sh
```

### 6. Update DNS

Point your domain to the ALB DNS name provided by Terraform:
- `yourdomain.com` → ALB DNS
- `www.yourdomain.com` → ALB DNS  
- `app.yourdomain.com` → ALB DNS

## Configuration Changes

### Environment Variables

The app now uses these AWS-specific variables:
- `AI_PROVIDER=bedrock` - Use AWS Bedrock for AI
- `AWS_REGION=us-east-1` - AWS region
- `AWS_S3_BUCKET` - S3 bucket for file storage

### AI Service Integration

The app now supports multiple AI providers:
- **Bedrock** (production) - Uses AWS Bedrock
- **OpenAI** (development) - Original OpenAI integration
- **Claude** - Direct Claude API

Set via `AI_PROVIDER` environment variable.

### Bedrock Models

Available models:
- `claude-opus-4-1-20250805` - Claude Opus 4.1 for complex tasks
- `claude-3-5-sonnet` - Claude 3.5 Sonnet for general use
- `claude-3-5-haiku` - Claude 3.5 Haiku for fast responses
- `titan-image-generator-v2` - Amazon Titan for image generation

## Cost Optimization

### Estimated Monthly Costs

- **ECS Fargate**: ~$40 (2 tasks, 0.25 vCPU, 0.5GB RAM each)
- **RDS**: ~$15 (db.t3.micro)
- **ALB**: ~$25
- **S3**: ~$5 (depends on storage)
- **Bedrock**: Usage-based (Claude Opus 4.1: $0.15/1K tokens)
- **Total**: ~$85/month + Bedrock usage

### Cost Saving Tips

1. Use Bedrock on-demand pricing (no commitments)
2. Implement caching for AI responses
3. Use smaller models when appropriate
4. Enable S3 lifecycle policies
5. Use RDS automated backups instead of snapshots

## Monitoring

### CloudWatch Dashboards

Monitor:
- ECS task health and resource usage
- RDS connections and performance
- ALB request counts and latency
- Bedrock API usage and costs

### Logs

All logs are sent to CloudWatch Logs:
- Application logs: `/ecs/agent-marketing`
- Access logs: ALB access logs to S3

## Backup Strategy

1. **Database**: Automated RDS backups (7-day retention)
2. **Code**: Git repository
3. **Uploads**: S3 versioning enabled
4. **Infrastructure**: Terraform state in S3

## Rollback Plan

If issues arise:

1. **Quick rollback**: Update ECS service to previous task definition
2. **Database rollback**: Restore from RDS snapshot
3. **Full rollback**: Keep Heroku running until AWS is stable

## Security Considerations

- All secrets in AWS Secrets Manager
- IAM roles for service access (no hardcoded credentials)
- VPC with private subnets for ECS and RDS
- SSL/TLS enforced at ALB
- S3 bucket encryption enabled

## Performance Optimizations

1. **CDN**: Consider adding CloudFront for static assets
2. **Caching**: Use ElastiCache for Rails caching
3. **Auto-scaling**: Configure ECS service auto-scaling
4. **Database**: Upgrade RDS instance type as needed

## Troubleshooting

### Common Issues

1. **Task fails to start**
   - Check CloudWatch logs
   - Verify secrets are accessible
   - Ensure Docker image is built correctly

2. **Database connection errors**
   - Check security group rules
   - Verify DATABASE_URL in Secrets Manager
   - Ensure RDS is in same VPC

3. **Bedrock access denied**
   - Check IAM task role permissions
   - Verify model access in Bedrock console
   - Check AWS region configuration

### Useful Commands

```bash
# View ECS logs
aws logs tail /ecs/agent-marketing --follow

# Check service status
aws ecs describe-services --cluster agent-marketing-cluster --services agent-marketing

# Force new deployment
aws ecs update-service --cluster agent-marketing-cluster --service agent-marketing --force-new-deployment

# Connect to database
psql $DATABASE_URL
```

## Next Steps

1. Set up CloudWatch alarms
2. Configure auto-scaling policies
3. Implement CI/CD with GitHub Actions
4. Add CloudFront CDN
5. Set up staging environment
