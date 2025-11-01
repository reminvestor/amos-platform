# Agent Marketing AWS Infrastructure

Terraform infrastructure for AWS Bedrock, Textract, Comprehend, and supporting services.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS Cloud                                 │
│                                                                   │
│  ┌──────────────┐     ┌─────────────────┐                       │
│  │  Rails App   │────▶│  Bedrock KB     │                       │
│  │  (ECS/EC2)   │     │  (Knowledge     │                       │
│  └──────────────┘     │   Base)         │                       │
│         │              └─────────────────┘                       │
│         │                       │                                 │
│         ▼                       ▼                                 │
│  ┌──────────────┐     ┌─────────────────┐                       │
│  │   Textract   │     │   OpenSearch    │                       │
│  │   (OCR)      │     │   Serverless    │                       │
│  └──────────────┘     └─────────────────┘                       │
│         │                       │                                 │
│         │                       │                                 │
│         ▼                       ▼                                 │
│  ┌──────────────┐     ┌─────────────────┐                       │
│  │  Comprehend  │     │   S3 Bucket     │                       │
│  │   (NLP)      │     │  (Documents)    │                       │
│  └──────────────┘     └─────────────────┘                       │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
terraform/
├── main.tf                    # Main infrastructure configuration
├── variables.tf               # Variable definitions
├── outputs.tf                 # Output definitions
├── README.md                  # This file
│
├── environments/              # Environment-specific configs
│   ├── dev.tfvars
│   ├── staging.tfvars
│   └── production.tfvars
│
└── modules/                   # Reusable Terraform modules
    ├── bedrock/              # Bedrock Knowledge Base
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── iam/                  # IAM roles and policies
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── s3/                   # S3 buckets
    ├── vpc/                  # VPC networking
    ├── opensearch/           # OpenSearch Serverless
    ├── lambda/               # Lambda functions
    ├── cloudwatch/           # CloudWatch logs and alarms
    └── cost_management/      # AWS Budgets and cost alerts
```

## Prerequisites

### 1. Install Terraform

```bash
# macOS
brew install terraform

# Or download from
# https://www.terraform.io/downloads
```

### 2. Install AWS CLI

```bash
# macOS
brew install awscli

# Configure AWS credentials
aws configure
```

### 3. Create S3 Backend Bucket (one-time setup)

```bash
# Create bucket for Terraform state
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

## Quick Start

### Deploy Development Environment

```bash
# From project root
./scripts/deploy-terraform.sh dev
```

### Deploy Production Environment

```bash
./scripts/deploy-terraform.sh production
```

## Manual Deployment

If you prefer manual deployment:

```bash
cd terraform

# Initialize Terraform
terraform init

# Review plan
terraform plan -var-file=environments/dev.tfvars

# Apply changes
terraform apply -var-file=environments/dev.tfvars
```

## Modules

### Bedrock Knowledge Base Module

Creates:
- Bedrock Knowledge Base
- S3 data source
- Lambda document processor
- S3 event notifications

Variables:
- `knowledge_base_name` - Name of the KB
- `embedding_model` - Model for embeddings (default: Titan v2)
- `chunk_size` - Text chunk size in tokens (default: 512)
- `chunk_overlap_percentage` - Overlap between chunks (default: 20%)

### IAM Module

Creates roles for:
- Bedrock Knowledge Base execution
- Lambda function execution
- Application (ECS/EC2) execution

Policies include:
- S3 access for documents
- OpenSearch access for vector storage
- Bedrock model invocation
- Textract and Comprehend access

### S3 Module

Creates:
- RAG document storage bucket
- Versioning enabled
- Intelligent-Tiering lifecycle policy
- Server-side encryption (KMS)

### VPC Module

Creates:
- VPC with public and private subnets
- Internet Gateway
- NAT Gateways for private subnets
- Route tables
- Security groups

### OpenSearch Module

Creates:
- OpenSearch Serverless collection
- Data access policy
- Encryption policy
- Network policy

### Lambda Module

Creates:
- Document processor function
- S3 event triggers
- VPC configuration
- CloudWatch logs

### CloudWatch Module

Creates:
- Log groups for services
- Metric alarms
- Cost anomaly detection
- Performance dashboards

### Cost Management Module

Creates:
- AWS Budget with alerts
- Cost allocation tags
- SNS topics for notifications

## Environment Configuration

### Development (dev.tfvars)

- Minimal resources for cost savings
- Single AZ deployment
- Smaller instance sizes
- 7-day log retention
- $500/month budget

### Staging (staging.tfvars)

- Multi-AZ for testing HA
- Production-like configuration
- 30-day log retention
- $1,000/month budget

### Production (production.tfvars)

- Multi-AZ high availability
- Large instance sizes
- Auto-scaling enabled
- 90-day log retention
- Deletion protection enabled
- $5,000/month budget

## Outputs

After deployment, Terraform provides these outputs:

```bash
# View all outputs
terraform output

# View specific output
terraform output bedrock_knowledge_base_id

# Export to JSON
terraform output -json > ../config/terraform-outputs-dev.json
```

Key outputs:
- `bedrock_knowledge_base_id` - KB ID for Rails app
- `s3_rag_bucket_name` - S3 bucket for documents
- `opensearch_endpoint` - OpenSearch endpoint
- `vpc_id` - VPC identifier
- `sns_alert_topic_arn` - SNS topic for alerts

## Cost Estimates

### Development Environment

- OpenSearch Serverless: ~$30/month (minimal OCUs)
- S3 Storage: ~$5/month (100GB)
- Lambda: ~$5/month (light usage)
- Textract: Pay per use (~$10/month)
- Comprehend: Pay per use (~$5/month)
- **Total: ~$55-75/month**

### Production Environment

- OpenSearch Serverless: ~$150/month (3 OCUs)
- S3 Storage: ~$25/month (500GB)
- Lambda: ~$20/month (moderate usage)
- Textract: Pay per use (~$100/month)
- Comprehend: Pay per use (~$50/month)
- Bedrock: Pay per use (~$200-500/month)
- **Total: ~$545-845/month**

## Testing Infrastructure

```bash
# Run infrastructure tests
./scripts/test-infrastructure.sh dev

# Test from Rails console
rails console
```

```ruby
# Test Bedrock KB
entity = Entity.first
kb = Aws::BedrockKnowledgeBaseService.instance
kb.create_knowledge_base(entity)

# Test document processing
processor = DocumentProcessorV2.instance
result = processor.process_document(entity, 'path/to/doc.pdf')

# Test query
kb.query(entity, "What is this about?")
```

## Updating Infrastructure

### Add New Resource

1. Add resource to appropriate module
2. Update variables if needed
3. Run `terraform plan` to review
4. Apply changes

### Change Existing Resource

1. Modify resource in module
2. Review plan carefully
3. Apply during maintenance window if production

### Destroy Infrastructure

**Warning**: This deletes all resources!

```bash
terraform destroy -var-file=environments/dev.tfvars
```

## State Management

Terraform state is stored in S3 with DynamoDB locking:

```hcl
backend "s3" {
  bucket         = "agent-marketing-terraform-state"
  key            = "infrastructure/terraform.tfstate"
  region         = "us-east-1"
  dynamodb_table = "terraform-state-lock"
  encrypt        = true
}
```

### View State

```bash
# List resources in state
terraform state list

# Show specific resource
terraform state show aws_bedrockagent_knowledge_base.main

# Pull state to local file
terraform state pull > terraform.tfstate.backup
```

## Troubleshooting

### Error: "NoCredentialProviders"
```bash
# Configure AWS credentials
aws configure

# Or set environment variables
export AWS_ACCESS_KEY_ID="your_key"
export AWS_SECRET_ACCESS_KEY="your_secret"
```

### Error: "Backend initialization required"
```bash
terraform init -reconfigure
```

### Error: "Resource already exists"
```bash
# Import existing resource
terraform import aws_s3_bucket.rag agent-marketing-dev-rag-storage

# Or force new resource
terraform taint aws_s3_bucket.rag
terraform apply
```

### Error: "Insufficient IAM permissions"
```bash
# Check required permissions
aws iam get-user
aws iam list-attached-user-policies --user-name YourUser

# Attach required policy
aws iam attach-user-policy \
  --user-name YourUser \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess
```

## Security Best Practices

1. **Never commit `.tfstate` files** (already in .gitignore)
2. **Use IAM roles** instead of access keys when possible
3. **Enable MFA** on AWS account
4. **Restrict S3 bucket access** with bucket policies
5. **Encrypt all data** at rest and in transit
6. **Enable CloudTrail** for audit logging
7. **Use least privilege** IAM policies
8. **Rotate credentials** regularly

## CI/CD Integration

Example GitHub Actions workflow:

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
      - uses: actions/checkout@v2
      - uses: hashicorp/setup-terraform@v2
      - name: Terraform Init
        run: terraform init
      - name: Terraform Plan
        run: terraform plan -var-file=environments/production.tfvars
      - name: Terraform Apply
        if: github.ref == 'refs/heads/main'
        run: terraform apply -auto-approve -var-file=environments/production.tfvars
```

## Support

- **Terraform Docs**: https://www.terraform.io/docs
- **AWS Provider Docs**: https://registry.terraform.io/providers/hashicorp/aws
- **Bedrock Docs**: https://docs.aws.amazon.com/bedrock/

---

**Last Updated**: 2025-01-31
**Terraform Version**: >= 1.5.0
**AWS Provider Version**: ~> 5.0