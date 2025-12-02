# Phase 4: Terraform Infrastructure as Code

## Overview

Phase 4 provides complete infrastructure-as-code (IaC) for deploying the AWS migration to any environment. This allows you to:

- 🚀 **Deploy in minutes**: One command to provision all AWS resources
- 🔄 **Reproducible environments**: Identical infrastructure for dev/staging/production
- 📊 **Cost tracking**: Built-in budgets and alerts
- 🔒 **Security**: Best practices baked in
- 📈 **Scalability**: Easily scale resources up or down
- 🛡️ **Disaster recovery**: Infrastructure can be recreated from code

## What Gets Deployed

### Core Infrastructure

1. **S3 Buckets**
   - RAG document storage
   - Intelligent-Tiering for cost optimization
   - Versioning and lifecycle policies
   - KMS encryption

2. **IAM Roles & Policies**
   - Bedrock Knowledge Base execution role
   - Application execution role (ECS/EC2)
   - Least privilege access policies

3. **Bedrock Knowledge Base**
   - OpenSearch Serverless collection
   - Vector index configuration
   - S3 data source integration
   - Embedding model configuration (Titan v2)

4. **Monitoring & Alerts**
   - CloudWatch log groups
   - Cost anomaly detection
   - Performance dashboards
   - SNS alerts

5. **Cost Management**
   - AWS Budgets with thresholds
   - Email notifications
   - Cost allocation tags

### Optional Components

- VPC with public/private subnets
- Lambda functions for async processing
- ECR repository for Docker images
- Secrets Manager for API keys
- KMS keys for encryption

## Quick Start

### Prerequisites

1. **AWS Account** with admin access
2. **Terraform** >= 1.5.0 installed
3. **AWS CLI** configured with credentials

### 1. Install Terraform

```bash
# macOS
brew install terraform

# Verify installation
terraform --version
```

### 2. Configure AWS Credentials

```bash
# Configure AWS CLI
aws configure

# Or set environment variables
export AWS_ACCESS_KEY_ID="your_key"
export AWS_SECRET_ACCESS_KEY="your_secret"
export AWS_REGION="us-east-1"
```

### 3. Initialize Backend (First Time Only)

```bash
# Create S3 bucket for Terraform state
aws s3 mb s3://agent-marketing-terraform-state --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket agent-marketing-terraform-state \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 4. Deploy Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init

# Review what will be created
terraform plan -var-file=environments/dev.tfvars

# Deploy infrastructure
terraform apply -var-file=environments/dev.tfvars
```

## Environment Configurations

### Development Environment

**File**: `terraform/environments/dev.tfvars`

**Characteristics**:
- Minimal resources for cost savings
- Single AZ deployment
- Smaller instance sizes
- 7-day log retention
- **Monthly budget**: $500

**Use case**: Local development, feature testing

### Staging Environment

**File**: `terraform/environments/staging.tfvars`

**Characteristics**:
- Multi-AZ for testing HA
- Production-like configuration
- 30-day log retention
- **Monthly budget**: $1,000

**Use case**: Pre-production testing, QA

### Production Environment

**File**: `terraform/environments/production.tfvars`

**Characteristics**:
- Multi-AZ high availability
- Large instance sizes
- Auto-scaling enabled
- 90-day log retention
- Deletion protection
- **Monthly budget**: $5,000

**Use case**: Live customer traffic

## Infrastructure Modules

### Bedrock Knowledge Base Module

**Location**: `terraform/modules/bedrock/`

**Creates**:
- Bedrock Knowledge Base
- OpenSearch Serverless collection
- Vector index with metadata filtering
- S3 data source configuration

**Key Variables**:
```hcl
knowledge_base_name = "amos-prod-kb"
embedding_model = "amazon.titan-embed-text-v2:0"
chunk_size = 512
chunk_overlap_percentage = 20
```

**Outputs**:
- `knowledge_base_id`: Use this in Rails app (ENV var)
- `opensearch_endpoint`: For direct queries
- `collection_id`: For monitoring

### S3 Storage Module

**Location**: `terraform/modules/s3/`

**Creates**:
- S3 bucket with encryption
- Lifecycle policies
- Versioning
- Intelligent-Tiering

**Features**:
- Automatic cost optimization via tiering
- 30-day transition to Infrequent Access
- 90-day transition to Archive
- Expiration policies for old versions

### IAM Module

**Location**: `terraform/modules/iam/`

**Creates**:
- `bedrock_kb_role`: For Knowledge Base operations
- `app_execution_role`: For ECS/EC2 instances
- Policies with least privilege

**Permissions Included**:
- S3 read/write for RAG bucket
- Bedrock model invocation
- Textract OCR processing
- Comprehend NLP analysis
- OpenSearch index access

### Monitoring Module

**Location**: `terraform/modules/cloudwatch/`

**Creates**:
- Log groups for each service
- Cost anomaly detection
- Performance dashboards
- SNS topics for alerts

**Alarms**:
- High Bedrock API error rate
- S3 bucket size threshold
- OpenSearch query latency
- Lambda function errors

### Cost Management Module

**Location**: `terraform/modules/cost_management/`

**Creates**:
- AWS Budget with thresholds
- Cost allocation tags
- Budget alerts (50%, 75%, 90%, 100%)

**Alert Levels**:
- 50% budget: Warning email
- 75% budget: Urgent email
- 90% budget: Critical email
- 100% budget: Limit exceeded

## Deployment Workflow

### Standard Deployment

```bash
cd terraform

# 1. Initialize (if first time or after adding modules)
terraform init

# 2. Select workspace (environment)
terraform workspace select dev  # or staging/production

# 3. Plan changes
terraform plan -var-file=environments/dev.tfvars -out=tfplan

# 4. Review plan
less tfplan

# 5. Apply changes
terraform apply tfplan

# 6. Save outputs
terraform output -json > ../config/terraform-outputs-dev.json
```

### Update Existing Infrastructure

```bash
# Make changes to .tf files

# Review changes
terraform plan -var-file=environments/dev.tfvars

# Apply only if changes look correct
terraform apply -var-file=environments/dev.tfvars
```

### Destroy Infrastructure

**⚠️ Warning**: This deletes ALL resources!

```bash
# Review what will be destroyed
terraform plan -destroy -var-file=environments/dev.tfvars

# Destroy infrastructure
terraform destroy -var-file=environments/dev.tfvars
```

## Integration with Rails App

### 1. Export Terraform Outputs

```bash
cd terraform
terraform output -json > ../config/terraform-outputs-production.json
```

### 2. Update Environment Variables

Add these to your `.env` file or secrets manager:

```bash
# From Terraform outputs
BEDROCK_KNOWLEDGE_BASE_ID=$(terraform output -raw bedrock_knowledge_base_id)
RAG_BUCKET=$(terraform output -raw s3_rag_bucket_name)
OPENSEARCH_ENDPOINT=$(terraform output -raw opensearch_endpoint)

# AWS credentials
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_key
AWS_SECRET_ACCESS_KEY=your_secret
```

### 3. Test Connection

```bash
rails console
```

```ruby
# Test Bedrock KB
entity = Entity.first
entity.update!(
  bedrock_knowledge_base_id: ENV['BEDROCK_KNOWLEDGE_BASE_ID'],
  use_bedrock_kb: true
)

# Query KB
kb = Aws::BedrockKnowledgeBaseService.instance
result = kb.query(entity, "test query")

puts "Found #{result[:results].count} results"
```

## Cost Estimation

### Development Environment (~$55-75/month)

- **OpenSearch Serverless**: $30/month (minimal OCUs)
- **S3 Storage**: $5/month (100GB)
- **Lambda**: $5/month (light usage)
- **Textract**: $10/month (pay per use)
- **Comprehend**: $5/month (pay per use)

### Production Environment (~$545-845/month)

- **OpenSearch Serverless**: $150/month (3 OCUs)
- **S3 Storage**: $25/month (500GB)
- **Lambda**: $20/month (moderate usage)
- **Textract**: $100/month (pay per use)
- **Comprehend**: $50/month (pay per use)
- **Bedrock**: $200-500/month (pay per use)

## Monitoring & Alerts

### CloudWatch Dashboards

After deployment, access dashboards:

```
https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=amos-production-dashboard
```

**Metrics Tracked**:
- Bedrock KB query latency
- S3 bucket size and requests
- Lambda invocations and errors
- OpenSearch query performance
- Cost trends

### SNS Alerts

Alert emails sent to:
- Budget thresholds (50%, 75%, 90%, 100%)
- Performance anomalies
- Error spikes
- Resource limits

### Cost Anomaly Detection

Automatically detects unusual spending patterns:
- Unexpected API usage spikes
- Resource provisioning changes
- Service cost increases

## State Management

### Backend Configuration

Terraform state is stored remotely in S3 with DynamoDB locking:

```hcl
backend "s3" {
  bucket         = "agent-marketing-terraform-state"
  key            = "infrastructure/terraform.tfstate"
  region         = "us-east-1"
  dynamodb_table = "terraform-state-lock"
  encrypt        = true
}
```

### Benefits:
- **Team collaboration**: Shared state
- **Locking**: Prevents concurrent modifications
- **Versioning**: State history in S3
- **Encryption**: State contains sensitive data

### State Commands

```bash
# List all resources
terraform state list

# Show specific resource
terraform state show module.bedrock_kb.aws_bedrockagent_knowledge_base.main

# Move resource (rename)
terraform state mv aws_s3_bucket.old aws_s3_bucket.new

# Remove resource from state (doesn't delete)
terraform state rm aws_s3_bucket.temp

# Import existing resource
terraform import module.s3.aws_s3_bucket.rag agent-marketing-dev-rag-storage
```

## Troubleshooting

### Error: "NoCredentialProviders"

```bash
# Check credentials
aws sts get-caller-identity

# If not working, reconfigure
aws configure
```

### Error: "Backend initialization required"

```bash
terraform init -reconfigure
```

### Error: "Resource already exists"

```bash
# Option 1: Import existing resource
terraform import aws_s3_bucket.rag your-bucket-name

# Option 2: Force recreation
terraform taint aws_s3_bucket.rag
terraform apply
```

### Error: "Insufficient IAM permissions"

**Required Permissions**:
- S3: Full access
- IAM: CreateRole, AttachRolePolicy
- Bedrock: Full access
- OpenSearch: Full access
- CloudWatch: Full access
- Budgets: Full access

**Solution**:
```bash
# Attach PowerUserAccess policy
aws iam attach-user-policy \
  --user-name YourUser \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess
```

### Error: "OpenSearch collection creation failed"

OpenSearch Serverless has account limits:
- Max 3 collections per account (default)
- Request limit increase via AWS Support

### State Lock Issues

```bash
# If state is locked from failed apply
terraform force-unlock LOCK_ID

# Get lock ID from error message
```

## Security Best Practices

1. ✅ **Never commit state files** (`.gitignore` configured)
2. ✅ **Use IAM roles** instead of access keys when possible
3. ✅ **Enable MFA** on AWS account
4. ✅ **Encrypt everything** (S3, state, secrets)
5. ✅ **Least privilege IAM** policies
6. ✅ **Rotate credentials** every 90 days
7. ✅ **Enable CloudTrail** for audit logs
8. ✅ **Use private subnets** for databases
9. ✅ **Enable VPC Flow Logs**
10. ✅ **Regular security scans**

## CI/CD Integration

### GitHub Actions Workflow

Create `.github/workflows/terraform-deploy.yml`:

```yaml
name: Deploy Infrastructure

on:
  push:
    branches: [main]
    paths: ['terraform/**']

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: hashicorp/setup-terraform@v2

      - name: Terraform Init
        working-directory: ./terraform
        run: terraform init

      - name: Terraform Plan
        working-directory: ./terraform
        run: terraform plan -var-file=environments/production.tfvars

      - name: Terraform Apply
        if: github.ref == 'refs/heads/main'
        working-directory: ./terraform
        run: terraform apply -auto-approve -var-file=environments/production.tfvars

      - name: Export Outputs
        run: terraform output -json > config/terraform-outputs.json

      - name: Commit Outputs
        run: |
          git config user.name "GitHub Actions"
          git config user.email "actions@github.com"
          git add config/terraform-outputs.json
          git commit -m "Update Terraform outputs [skip ci]" || true
          git push
```

## Migration Path

### From Manual AWS Setup

If you already have AWS resources:

1. **Inventory existing resources**
   ```bash
   aws bedrock list-knowledge-bases
   aws s3 ls
   aws opensearchserverless list-collections
   ```

2. **Import into Terraform**
   ```bash
   terraform import module.bedrock_kb.aws_bedrockagent_knowledge_base.main YOUR_KB_ID
   terraform import module.s3.aws_s3_bucket.rag your-bucket-name
   ```

3. **Run plan to verify**
   ```bash
   terraform plan
   # Should show no changes if imports correct
   ```

### From Other IaC Tools

If using CloudFormation, Pulumi, or CDK:

1. Export current infrastructure
2. Create matching Terraform configs
3. Import resources one-by-one
4. Verify with `terraform plan`
5. Cut over during maintenance window

## Advanced Topics

### Multi-Region Deployment

```hcl
# terraform/main.tf
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "eu_west_1"
  region = "eu-west-1"
}

module "bedrock_kb_us" {
  source = "./modules/bedrock"
  providers = { aws = aws.us_east_1 }
  # ...
}

module "bedrock_kb_eu" {
  source = "./modules/bedrock"
  providers = { aws = aws.eu_west_1 }
  # ...
}
```

### Custom Modules

Create reusable modules:

```bash
# Create new module
mkdir -p terraform/modules/custom_service

# Add module files
touch terraform/modules/custom_service/{main.tf,variables.tf,outputs.tf}

# Use in main.tf
module "custom" {
  source = "./modules/custom_service"
  # ...
}
```

### Workspaces

Use workspaces for environments:

```bash
# Create workspace
terraform workspace new staging

# Switch workspace
terraform workspace select production

# List workspaces
terraform workspace list

# Current workspace
terraform workspace show
```

## Next Steps After Deployment

1. **Configure Monitoring**
   - Set up CloudWatch dashboards
   - Configure SNS alert subscriptions
   - Enable cost anomaly detection

2. **Test Infrastructure**
   - Upload test documents to S3
   - Query Bedrock Knowledge Base
   - Verify monitoring/alerts

3. **Update Rails App**
   - Add Terraform outputs to .env
   - Deploy updated application
   - Run integration tests

4. **Document Runbooks**
   - Deployment procedures
   - Incident response
   - Disaster recovery

5. **Train Team**
   - Terraform workflows
   - Monitoring dashboards
   - Cost optimization

## Support Resources

- **Terraform Docs**: https://www.terraform.io/docs
- **AWS Provider**: https://registry.terraform.io/providers/hashicorp/aws
- **Bedrock Docs**: https://docs.aws.amazon.com/bedrock/
- **OpenSearch Serverless**: https://docs.aws.amazon.com/opensearch-service/latest/developerguide/serverless.html

---

**Phase 4 Complete!** 🎉

You now have production-ready infrastructure that can be deployed, updated, and managed entirely through code.
