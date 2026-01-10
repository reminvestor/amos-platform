# AWS Bedrock Migration Guide

## Overview

This guide walks you through migrating from the existing Pinecone + Docling setup to AWS Bedrock, Textract, and Comprehend for a fully AWS-native AI infrastructure.

## Migration Phases

### Phase 1: OCR System (Completed) ✅
- Dual-mode OCR (Textract + Docling fallback)
- Intelligent provider selection
- Cost tracking per entity

### Phase 2: RAG System (Completed) ✅
- Bedrock Knowledge Base implementation
- S3 + OpenSearch Serverless storage
- Document ingestion pipeline
- Query and retrieval interfaces

### Phase 3: NLP Enhancement (Completed) ✅
- Amazon Comprehend integration
- Entity extraction
- Sentiment analysis
- Key phrase detection
- PII detection

### Phase 4: Infrastructure (Completed) ✅
- Terraform modules for all AWS resources
- Environment configurations (dev, staging, production)
- Deployment and testing scripts

## Prerequisites

### 1. AWS Account Setup

```bash
# Configure AWS CLI
aws configure

# Verify access
aws sts get-caller-identity
```

### 2. Required IAM Permissions

Your AWS user/role needs permissions for:
- Bedrock (Knowledge Base, Agent, Models)
- Textract
- Comprehend
- S3
- OpenSearch Serverless
- Lambda
- IAM (for role creation)
- CloudWatch Logs

### 3. Install Dependencies

```bash
# Terraform
brew install terraform  # macOS
# or download from https://www.terraform.io/downloads

# AWS CLI v2
brew install awscli  # macOS

# Add to Gemfile
gem 'aws-sdk-bedrockagent'
gem 'aws-sdk-bedrockagentruntime'
gem 'aws-sdk-textract'
gem 'aws-sdk-comprehend'
gem 'aws-sdk-s3'

bundle install
```

## Step-by-Step Migration

### Step 1: Deploy Infrastructure

```bash
# Development environment
chmod +x scripts/deploy-terraform.sh
./scripts/deploy-terraform.sh dev

# Production environment
./scripts/deploy-terraform.sh production
```

This creates:
- VPC with public/private subnets
- S3 bucket for documents
- OpenSearch Serverless collection
- Bedrock Knowledge Base
- IAM roles and policies
- Lambda functions for processing
- CloudWatch log groups
- Cost monitoring

### Step 2: Update Environment Variables

After Terraform deployment, update your `.env` file:

```bash
# Get values from Terraform outputs
cd terraform
terraform output -json > ../config/terraform-outputs-dev.json

# Add to .env
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key

# From Terraform outputs
BEDROCK_KB_ID=$(terraform output -raw bedrock_knowledge_base_id)
RAG_BUCKET=$(terraform output -raw s3_rag_bucket_name)
OPENSEARCH_ENDPOINT=$(terraform output -raw opensearch_endpoint)

# Optional: Role ARNs for production
BEDROCK_KB_ROLE_ARN=arn:aws:iam::ACCOUNT:role/bedrock-kb-role
COMPREHEND_ROLE_ARN=arn:aws:iam::ACCOUNT:role/comprehend-role
```

### Step 3: Run Database Migrations

```bash
# Run new migrations for AWS fields
rails db:migrate

# This creates:
# - bedrock_knowledge_base_id on entities
# - entity_usage_metrics table
# - entity_cost_summaries table
# - ocr_metrics table
```

### Step 4: Migrate Existing Documents (Optional)

If you have existing documents in Pinecone:

```ruby
# Rails console
rails console

# Migrate all entities
Entity.find_each do |entity|
  puts "Migrating entity: #{entity.name}"

  kb_service = Aws::BedrockKnowledgeBaseService.instance
  result = kb_service.migrate_from_pinecone(entity, batch_size: 100)

  puts "  Migrated: #{result[:migrated]}"
  puts "  Failed: #{result[:failed]}"
end
```

### Step 5: Test the Integration

```bash
# Run infrastructure tests
chmod +x scripts/test-infrastructure.sh
./scripts/test-infrastructure.sh dev

# Test document processing
rails console
```

```ruby
# In Rails console
entity = Entity.first

# Test document upload
file_path = Rails.root.join('test/fixtures/files/sample.pdf')
processor = DocumentProcessorV2.instance
result = processor.process_document(entity, file_path)

puts "Success: #{result[:success]}"
puts "Steps: #{result[:steps].map { |s| s[:step] }.join(', ')}"

# Test knowledge query
kb_service = Aws::BedrockKnowledgeBaseService.instance
query_result = kb_service.query(entity, "What is this document about?")

puts "Results: #{query_result[:result_count]}"
query_result[:results].each do |r|
  puts "  - #{r[:content][0..100]}... (score: #{r[:score]})"
end

# Test RAG generation
response = kb_service.retrieve_and_generate(
  entity,
  "Summarize the key points from the documents",
  nil
)

puts "Response: #{response[:response]}"
```

### Step 6: Update Scout Integration

Replace old Pinecone queries with new Bedrock KB queries:

```ruby
# OLD CODE (Pinecone):
# results = pinecone_service.query(query_embedding, namespace: entity.id)

# NEW CODE (Bedrock KB):
integration = ScoutAwsIntegration.instance
result = integration.process_message(
  entity,
  user_message,
  session_id,
  {
    enable_nlp: true,
    prefer_fast_model: true  # Use Haiku for speed
  }
)

# Response includes:
# - RAG-enhanced answer
# - Citations from knowledge base
# - NLP analysis (sentiment, entities)
# - Cost tracking
```

### Step 7: Enable Cost Tracking

Cost tracking is automatic. View in admin dashboard:

```
https://yourdomain.com/admin/entity_costs
```

## Feature Comparison

### Before (Pinecone + Docling)

| Feature | Implementation | Cost |
|---------|---------------|------|
| OCR | Docling only | Free (compute) |
| Vector DB | Pinecone | $70/month |
| Embeddings | OpenAI | Variable |
| NLP | None | N/A |
| Query | Pinecone API | Included |

**Total: ~$100-200/month** (varies with usage)

### After (AWS Bedrock)

| Feature | Implementation | Cost |
|---------|---------------|------|
| OCR | Textract + Docling | $1.20/1K pages |
| Vector DB | OpenSearch Serverless | $0.22/OCU-hour |
| Embeddings | Titan v2 | $0.08/1M tokens |
| NLP | Comprehend | $0.00008/100 chars |
| Query | Bedrock KB | $0.20/1K queries |
| Generation | Claude 3.5 | $3/$15 per 1M tokens |

**Total: ~$150-300/month** (cost-neutral to slightly higher, but better features)

## Cost Optimization Tips

### 1. Use Intelligent Tiering for S3
```ruby
# Automatically transitions old documents to cheaper storage
# Configured in Terraform by default
```

### 2. Choose Right Model for Task
```ruby
# Fast/cheap queries
model: 'claude-3-5-haiku'  # $0.25/$1.25 per 1M tokens

# Complex analysis
model: 'claude-3-5-sonnet'  # $3/$15 per 1M tokens
```

### 3. Batch Document Processing
```ruby
# Process multiple documents at once
processor = DocumentProcessorV2.instance
results = processor.process_batch(entity, file_paths, {
  enable_nlp: true,
  detect_pii: true
})
```

### 4. Cache Query Results
```ruby
# Cache frequent queries in Rails cache
cache_key = "kb_query_#{entity.id}_#{Digest::SHA256.hexdigest(query)}"
Rails.cache.fetch(cache_key, expires_in: 1.hour) do
  kb_service.query(entity, query)
end
```

### 5. Monitor Costs per Entity
```ruby
# Track which customers cost the most
tracker = EntityCostTracker.new(entity)
monthly_cost = tracker.get_total_cost(
  start_date: 30.days.ago,
  end_date: Date.current
)

# Get cost breakdown
costs_by_category = tracker.get_costs_by_category
```

## Rollback Plan

If you need to rollback:

### 1. Switch OCR Back to Docling Only
```ruby
# In ocr/dual_mode_service.rb
ENV['OCR_PROVIDER'] = 'docling'
ENV['OCR_FALLBACK_ENABLED'] = 'false'
```

### 2. Keep Using Existing Vector DB
```ruby
# Don't update document processing to use Bedrock KB
# Continue using existing Pinecone integration
```

### 3. Destroy Terraform Infrastructure (if needed)
```bash
cd terraform
terraform destroy -var-file=environments/dev.tfvars
```

## Troubleshooting

### Issue: "Knowledge Base not found"
```ruby
# Create knowledge base manually
entity = Entity.find(YOUR_ENTITY_ID)
kb_service = Aws::BedrockKnowledgeBaseService.instance
kb = kb_service.create_knowledge_base(entity)
```

### Issue: "Insufficient IAM permissions"
```bash
# Check IAM role has required policies
aws iam get-role --role-name agent-marketing-dev-app-role

# Attach missing policies
terraform apply -var-file=environments/dev.tfvars
```

### Issue: "Textract quota exceeded"
```ruby
# Switch back to Docling temporarily
ENV['OCR_PROVIDER'] = 'docling'

# Or request quota increase
# https://console.aws.amazon.com/servicequotas/
```

### Issue: "High costs detected"
```ruby
# View cost breakdown
entity = Entity.find(YOUR_ENTITY_ID)
tracker = EntityCostTracker.new(entity)

costs = tracker.get_costs_by_category
puts costs.inspect

# Identify top cost drivers
drivers = tracker.identify_cost_drivers
puts drivers.inspect
```

## Support and Resources

- **AWS Bedrock Documentation**: https://docs.aws.amazon.com/bedrock/
- **Textract Developer Guide**: https://docs.aws.amazon.com/textract/
- **Comprehend Developer Guide**: https://docs.aws.amazon.com/comprehend/
- **Terraform AWS Provider**: https://registry.terraform.io/providers/hashicorp/aws/

## Next Steps

After migration:

1. **Optimize chunk sizes** for your documents
2. **Fine-tune retrieval** parameters
3. **Set up CloudWatch alarms** for cost thresholds
4. **Create backup strategy** for S3 documents
5. **Implement vector index optimization**
6. **Set up CI/CD** for infrastructure updates

---

**Migration Status**: ✅ All phases complete
**Documentation**: Complete
**Testing**: Scripts provided
**Support**: Full Terraform infrastructure