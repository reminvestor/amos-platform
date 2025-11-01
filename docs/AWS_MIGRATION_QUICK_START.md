# AWS Migration Quick Start Guide

## Prerequisites

### 1. AWS Account Setup
```bash
# Install AWS CLI if not already installed
brew install awscli

# Configure AWS credentials
aws configure
# Enter:
# - AWS Access Key ID
# - AWS Secret Access Key
# - Default region: us-east-1
# - Default output format: json
```

### 2. Required AWS Service Quotas
Request these quota increases immediately (can take 24-48 hours):

```bash
# Request via AWS CLI
aws service-quotas request-service-quota-increase \
  --service-code textract \
  --quota-code L-CA6B4228 \
  --desired-value 50

aws service-quotas request-service-quota-increase \
  --service-code bedrock \
  --quota-code L-9F3E5D2B \
  --desired-value 10
```

### 3. IAM Roles Setup

Create these roles in AWS Console or via Terraform:

```hcl
# terraform/iam_roles.tf
resource "aws_iam_role" "bedrock_kb_role" {
  name = "BedrockKnowledgeBaseRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "bedrock_kb_s3" {
  role       = aws_iam_role.bedrock_kb_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "bedrock_kb_opensearch" {
  role       = aws_iam_role.bedrock_kb_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonOpenSearchServiceFullAccess"
}
```

## Day 1: Textract Integration

### Step 1: Add Required Gems
```ruby
# Gemfile
gem 'aws-sdk-textract', '~> 1.0'
gem 'aws-sdk-comprehend', '~> 1.0'
gem 'aws-sdk-bedrockagent', '~> 1.0'
gem 'aws-sdk-bedrockagentruntime', '~> 1.0'
```

```bash
bundle install
```

### Step 2: Environment Variables
```bash
# .env.development
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key

# S3 Bucket (create if doesn't exist)
RAG_STORAGE_BUCKET=agent-marketing-rag-storage-dev

# Feature Flags
USE_TEXTRACT=true
USE_BEDROCK_KB=false  # Enable after Phase 2
USE_COMPREHEND=false  # Enable after Phase 3
```

### Step 3: Create S3 Bucket
```bash
# Create bucket with versioning
aws s3api create-bucket \
  --bucket agent-marketing-rag-storage-dev \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket agent-marketing-rag-storage-dev \
  --versioning-configuration Status=Enabled
```

### Step 4: Implement Textract Service
```bash
# Copy the service implementation
mkdir -p app/services/aws
# Copy the TextractService code from AWS_SERVICE_IMPLEMENTATION_GUIDE.md
```

### Step 5: Test Textract Integration
```ruby
# rails console
entity = Entity.first
service = Aws::TextractService.new(entity)

# Test with a simple PDF
result = service.process_document("test.pdf", extract_tables: true)
puts result[:raw_text]
```

## Day 2: Bedrock Knowledge Base Setup

### Step 1: Create OpenSearch Serverless Collection
```bash
# Via AWS CLI
aws opensearchserverless create-collection \
  --name amos-rag-dev \
  --type VECTORSEARCH
```

### Step 2: Update Entity Model
```bash
# Generate migration
rails g migration AddBedrockFieldsToEntities

# Edit migration
class AddBedrockFieldsToEntities < ActiveRecord::Migration[7.1]
  def change
    add_column :entities, :bedrock_kb_id, :string
    add_column :entities, :bedrock_data_source_id, :string
    add_column :entities, :opensearch_collection_arn, :string
    add_column :entities, :use_bedrock_kb, :boolean, default: false
    add_index :entities, :bedrock_kb_id
  end
end

rails db:migrate
```

### Step 3: Implement Bedrock KB Service
```bash
# Copy the BedrockKnowledgeBaseService implementation
# Create background jobs
```

### Step 4: Test Knowledge Base Creation
```ruby
# rails console
entity = Entity.first
service = Aws::BedrockKnowledgeBaseService.new(entity)

# Create knowledge base
kb_id = service.ensure_knowledge_base
puts "Created KB: #{kb_id}"

# Add a document
result = service.add_document("sample.pdf", title: "Test Document")

# Query the knowledge base (after ingestion completes)
results = service.query("What is in the document?")
puts results
```

## Testing Strategy

### 1. Unit Tests (VCR Cassettes)
```ruby
# test/test_helper.rb
VCR.configure do |config|
  config.cassette_library_dir = "test/vcr_cassettes"
  config.hook_into :webmock
  config.filter_sensitive_data('<AWS_ACCESS_KEY>') { ENV['AWS_ACCESS_KEY_ID'] }
  config.filter_sensitive_data('<AWS_SECRET_KEY>') { ENV['AWS_SECRET_ACCESS_KEY'] }
end
```

### 2. Integration Tests
```bash
# Run AWS integration tests
rails test test/services/aws/

# Run specific service test
rails test test/services/aws/textract_service_test.rb
```

### 3. Performance Testing
```ruby
# lib/tasks/aws_performance.rake
namespace :aws do
  desc "Benchmark Textract vs Docling"
  task benchmark_ocr: :environment do
    entity = Entity.first
    test_file = "test/fixtures/files/multi_page_report.pdf"

    # Docling benchmark
    docling_time = Benchmark.realtime do
      DoclingProcessor.new.process_file(test_file)
    end

    # Textract benchmark
    textract_time = Benchmark.realtime do
      Aws::TextractService.new(entity).process_document(test_file)
    end

    puts "Docling: #{docling_time}s"
    puts "Textract: #{textract_time}s"
    puts "Improvement: #{((docling_time - textract_time) / docling_time * 100).round(2)}%"
  end
end
```

## Rollout Strategy

### Phase 1: Shadow Mode (Week 1)
```ruby
# app/services/document_processor_service.rb
class DocumentProcessorService
  def process(document)
    # Process with both systems
    docling_result = process_with_docling(document)
    textract_result = process_with_textract(document) if ENV['SHADOW_TEXTRACT'] == 'true'

    # Log comparison metrics
    if textract_result
      log_comparison(docling_result, textract_result)
    end

    # Return original system result
    docling_result
  end
end
```

### Phase 2: Percentage Rollout (Week 2)
```ruby
# app/services/rag_service.rb
class RagService
  def initialize(entity)
    @entity = entity
    @use_bedrock = should_use_bedrock?(entity)
  end

  private

  def should_use_bedrock?(entity)
    return true if entity.use_bedrock_kb? # Entity override

    # Percentage rollout
    percentage = ENV.fetch('BEDROCK_KB_ROLLOUT_PERCENTAGE', '0').to_i
    rand(100) < percentage
  end
end
```

### Phase 3: Full Rollout (Week 3)
```yaml
# config/settings.yml
production:
  use_textract: true
  use_bedrock_kb: true
  use_comprehend: true
  fallback_enabled: true  # Keep old system as fallback
```

## Monitoring Dashboard

### CloudWatch Dashboard Setup
```bash
# Create dashboard via CLI
aws cloudwatch put-dashboard \
  --dashboard-name AMOS-AWS-Migration \
  --dashboard-body file://cloudwatch-dashboard.json
```

### Key Metrics to Track
1. **Textract**
   - Processing time per page
   - Success/failure rate
   - Cost per document

2. **Bedrock KB**
   - Query latency
   - Ingestion success rate
   - Chunks retrieved per query

3. **Comprehend**
   - Analysis time
   - Entity detection accuracy
   - Sentiment distribution

## Troubleshooting

### Common Issues and Solutions

1. **Textract Timeout**
```ruby
# Increase timeout in service
@client = ::Aws::Textract::Client.new(
  http_read_timeout: 300  # 5 minutes
)
```

2. **Bedrock KB Not Found**
```ruby
# Ensure KB is created
service = Aws::BedrockKnowledgeBaseService.new(entity)
service.ensure_knowledge_base  # Creates if doesn't exist
```

3. **S3 Access Denied**
```bash
# Check IAM role permissions
aws iam get-role-policy --role-name BedrockKnowledgeBaseRole --policy-name S3Access
```

4. **Rate Limiting**
```ruby
# Implement exponential backoff
retry_on Aws::Textract::Errors::ThrottlingException,
         wait: :exponentially_longer,
         attempts: 5
```

## Cost Optimization

### 1. Use Intelligent Tiering
```bash
# Move old documents to cheaper storage
aws s3api put-bucket-lifecycle-configuration \
  --bucket agent-marketing-rag-storage \
  --lifecycle-configuration file://lifecycle.json
```

### 2. Optimize Textract Usage
```ruby
# Use sync for small docs, async for large
if document.pages <= 1
  process_sync(document)  # Cheaper
else
  process_async(document)  # More expensive but necessary
end
```

### 3. Cache Comprehend Results
```ruby
# Cache analysis results
Rails.cache.fetch("comprehend:#{document.id}", expires_in: 30.days) do
  comprehend_service.analyze_document(document.text)
end
```

## Next Steps

1. **Week 1**
   - [ ] Complete Textract integration
   - [ ] Set up monitoring
   - [ ] Run performance benchmarks

2. **Week 2**
   - [ ] Deploy Bedrock Knowledge Base
   - [ ] Migrate first 10% of entities
   - [ ] Monitor costs and performance

3. **Week 3**
   - [ ] Add Comprehend enhancement
   - [ ] Increase rollout to 50%
   - [ ] Prepare production deployment

4. **Week 4**
   - [ ] Full production deployment
   - [ ] Disable legacy system
   - [ ] Documentation and training

## Support Resources

- AWS Textract Documentation: https://docs.aws.amazon.com/textract/
- Bedrock Knowledge Bases Guide: https://docs.aws.amazon.com/bedrock/latest/userguide/knowledge-base.html
- Comprehend Developer Guide: https://docs.aws.amazon.com/comprehend/
- AWS Ruby SDK: https://github.com/aws/aws-sdk-ruby

## Emergency Rollback

If critical issues arise:

```bash
# 1. Disable AWS services via environment
heroku config:set USE_TEXTRACT=false USE_BEDROCK_KB=false -a production-app

# 2. Or use feature flags
rails c
SystemSetting.set('use_aws_services', false)

# 3. Monitor legacy system
tail -f log/production.log | grep "Fallback to Docling"
```

## Contact

For questions or issues:
- Create issue in GitHub
- Slack: #aws-migration channel
- AWS Support: via AWS Console (Business Support required)