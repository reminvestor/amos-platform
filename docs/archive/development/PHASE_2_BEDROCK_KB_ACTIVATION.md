# Phase 2: Bedrock Knowledge Base Activation Guide

## Overview

Phase 2 enables AWS Bedrock Knowledge Bases as a fully managed RAG backend. This eliminates the need to manage vector databases, chunking, and embeddings yourself—AWS handles it all via OpenSearch Serverless.

**What's Included in Phase 2:**
- ✅ Intelligent RAG mode selection (auto-detects best backend)
- ✅ Bedrock KB integration in HybridRagQueryService
- ✅ Admin UI for KB creation and management
- ✅ Automatic fallback to pgvector/Pinecone
- ✅ Per-entity KB configuration
- ✅ Ingestion job monitoring

## Prerequisites

Before activating Phase 2, ensure:

1. **Phase 1 Complete**: AWS Textract OCR integration is working
2. **AWS Credentials Configured**: IAM permissions for Bedrock Knowledge Bases
3. **S3 Bucket Ready**: RAG_BUCKET env var configured
4. **Database Migration**: Bedrock KB fields added to entities table

### Required IAM Permissions

Your AWS IAM role needs these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:CreateKnowledgeBase",
        "bedrock:GetKnowledgeBase",
        "bedrock:ListKnowledgeBases",
        "bedrock:DeleteKnowledgeBase",
        "bedrock:StartIngestionJob",
        "bedrock:GetIngestionJob",
        "bedrock:ListIngestionJobs",
        "bedrock:Retrieve",
        "bedrock:RetrieveAndGenerate"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "aoss:CreateAccessPolicy",
        "aoss:CreateCollection",
        "aoss:CreateSecurityPolicy",
        "aoss:GetAccessPolicy",
        "aoss:ListAccessPolicies",
        "aoss:UpdateAccessPolicy"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::your-rag-bucket",
        "arn:aws:s3:::your-rag-bucket/*"
      ]
    }
  ]
}
```

## Activation Steps

### 1. Run Database Migration

```bash
rails db:migrate
```

This adds three columns to the `entities` table:
- `bedrock_knowledge_base_id` - Stores the KB ID
- `bedrock_kb_status` - Tracks KB status (CREATING, ACTIVE, etc.)
- `bedrock_last_ingestion_job_id` - Tracks sync job ID

### 2. Configure Environment Variables

Add to `.env`:

```bash
# Enable Bedrock Knowledge Base (default: enabled)
AWS_BEDROCK_KB_ENABLED=true

# S3 bucket for RAG document storage (required)
RAG_BUCKET=your-rag-bucket-name

# AWS credentials (already configured from Phase 1)
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_key_id
AWS_SECRET_ACCESS_KEY=your_secret_key
```

### 3. Restart Rails Server

```bash
# Docker Compose
docker compose restart web

# Or local development
bin/dev
```

### 4. Verify Services Are Loaded

```bash
rails runner "
  puts '🔍 Checking Bedrock KB Service...'
  service = Aws::BedrockKnowledgeBaseService.instance
  puts '✅ BedrockKnowledgeBaseService loaded'

  puts ''
  puts '🔍 Checking RAG Mode Selector...'
  entity = Entity.first
  selector = RagModeSelector.new(entity)
  puts \"✅ RAG Mode: #{selector.mode}\"
  puts \"   Available modes: #{selector.available_modes.join(', ')}\"
"
```

## Using the Admin UI

### Access the Admin Interface

Navigate to: **Admin → Bedrock KB Management**

Direct URL: `/admin/bedrock_kb`

### Dashboard Overview

The index page shows:
- **Statistics**: Total entities, KB-enabled count, hybrid mode count
- **RAG Modes Documentation**: Explanation of each mode
- **Entity List**: All entities with their current RAG mode and KB status

### Managing an Entity's Knowledge Base

Click **"Manage"** on any entity to:

1. **Create Knowledge Base** (if not exists)
   - Creates OpenSearch Serverless collection
   - Configures S3 data source
   - Sets up access policies
   - Returns KB ID (stored in entity record)

2. **Sync Documents**
   - Triggers ingestion job to sync S3 docs to OpenSearch
   - Monitors job status (IN_PROGRESS → COMPLETE)
   - Updates last ingestion job ID

3. **Enable Bedrock KB Mode**
   - Switches entity to use Bedrock KB for RAG queries
   - Sets `use_bedrock_kb = true` on entity
   - Automatic via RagModeSelector

4. **Disable Bedrock KB Mode**
   - Falls back to hybrid (pgvector + Pinecone) mode
   - Sets `use_bedrock_kb = false`
   - KB remains available for re-activation

## RAG Mode Selection Logic

The system automatically selects the best RAG backend using `RagModeSelector`:

### Priority 1: Bedrock KB
**Requirements:**
- Entity has `use_bedrock_kb = true`
- Entity has `bedrock_knowledge_base_id` present
- `AWS_BEDROCK_KB_ENABLED != 'false'` in environment

**When to use:** High-scale production entities needing fully managed RAG

### Priority 2: Hybrid (pgvector + Pinecone)
**Requirements:**
- `PINECONE_API_KEY` present in environment

**When to use:** Standard production entities with optional cloud backup

### Priority 3: pgvector Only (Fallback)
**Requirements:** None (always available)

**When to use:** Development, testing, or lightweight production

## How It Works

### Document Upload Flow

1. **User uploads document** (PDF, image, text file)
2. **Document processed** via Textract or Docling (Phase 1)
3. **Chunked and stored** in PostgreSQL (pgvector)
4. **Uploaded to S3** for Bedrock KB ingestion
5. **Ingestion job triggered** (if Bedrock KB enabled)
6. **OpenSearch indexed** by AWS Bedrock

### Query Flow (Bedrock KB Enabled)

1. **User asks question** in Scout
2. **RagModeSelector detects** Bedrock KB is available
3. **HybridRagQueryService queries three sources in parallel:**
   - pgvector (local fast search)
   - Bedrock KB (managed OpenSearch)
   - Keyword search (PostgreSQL full-text)
4. **Results merged and reranked** by relevance
5. **Top K chunks returned** to AI for answer generation

### Three-Way Result Merging

The `merge_and_rerank_multi` method:
- Combines results from all three sources
- Deduplicates by content similarity
- Takes maximum score for duplicates
- Prefers Bedrock KB source if available
- Returns top K by combined score

## Testing Phase 2

### Test 1: Verify RAG Mode Selection

```bash
rails runner "
  entity = Entity.first
  selector = RagModeSelector.new(entity)

  puts '🎯 Current RAG Mode: ' + selector.mode.to_s
  puts '📊 Mode Info: ' + selector.mode_info.inspect
  puts '✅ Mode Valid: ' + selector.mode_valid?.to_s
  puts ''
  puts '🔍 Available Modes:'
  selector.available_modes.each { |m| puts \"   - #{m}\" }
  puts ''
  puts '🔧 Bedrock KB Available: ' + selector.bedrock_kb_available?.to_s
  puts '🔧 Pinecone Available: ' + selector.pinecone_available?.to_s
"
```

### Test 2: Create Knowledge Base

```bash
rails runner "
  entity = Entity.find_by(subdomain: 'demo') # Change to your entity
  kb_service = Aws::BedrockKnowledgeBaseService.instance

  puts '🔨 Creating Knowledge Base for: ' + entity.name
  kb = kb_service.create_knowledge_base(entity)

  puts ''
  puts '✅ Knowledge Base Created!'
  puts '   KB ID: ' + kb.knowledge_base_id
  puts '   Status: ' + kb.status
  puts ''

  entity.reload
  puts '✅ Entity Updated:'
  puts '   bedrock_knowledge_base_id: ' + entity.bedrock_knowledge_base_id.to_s
  puts '   bedrock_kb_status: ' + entity.bedrock_kb_status.to_s
"
```

### Test 3: Sync Documents

```bash
rails runner "
  entity = Entity.find_by(subdomain: 'demo')
  kb_service = Aws::BedrockKnowledgeBaseService.instance

  puts '🔄 Starting Ingestion Job...'
  job = kb_service.start_ingestion_job(entity.bedrock_knowledge_base_id, entity)

  puts ''
  puts '✅ Ingestion Job Started!'
  puts '   Job ID: ' + job.ingestion_job_id
  puts '   Status: ' + job.status
  puts ''

  # Wait and check status
  sleep 5
  status = kb_service.check_ingestion_status(entity)
  puts '📊 Current Status: ' + status[:status]
"
```

### Test 4: Query Bedrock KB

```bash
rails runner "
  entity = Entity.find_by(subdomain: 'demo')

  # Enable Bedrock KB mode
  selector = RagModeSelector.new(entity)
  selector.switch_mode!(:bedrock_kb)

  puts '✅ Bedrock KB Mode Enabled'
  puts ''

  # Perform query
  service = HybridRagQueryService.new(entity)
  results = service.search_with_scores('What is our company about?', top_k: 5)

  puts '🔍 Query Results:'
  results.each_with_index do |r, i|
    puts \"   #{i + 1}. [Score: #{r[:combined_score]}] #{r[:content][0..100]}...\"
    puts \"      Source: #{r[:source]}\"
  end
"
```

## Monitoring and Troubleshooting

### Check Knowledge Base Status

Via Admin UI:
1. Go to `/admin/bedrock_kb`
2. Click "Manage" on entity
3. View "Knowledge Base Status" card

Via Rails Console:
```ruby
entity = Entity.find(1)
kb_service = Aws::BedrockKnowledgeBaseService.instance
kb_details = kb_service.send(:describe_knowledge_base, entity.bedrock_knowledge_base_id)

puts "Status: #{kb_details.status}"
puts "Created: #{kb_details.created_at}"
puts "Updated: #{kb_details.updated_at}"
```

### Check Ingestion Job Status

Via Admin UI:
1. Go to entity's Bedrock KB management page
2. View "Last Ingestion Job" section

Via Rails Console:
```ruby
entity = Entity.find(1)
kb_service = Aws::BedrockKnowledgeBaseService.instance
status = kb_service.check_ingestion_status(entity)

puts "Job ID: #{status[:job_id]}"
puts "Status: #{status[:status]}"
puts "Started: #{status[:started_at]}"
puts "Completed: #{status[:completed_at]}"
puts "Statistics: #{status[:statistics]}"
```

### Common Issues

#### Issue 1: "Knowledge Base not found"

**Cause:** KB was deleted from AWS but entity still has KB ID

**Fix:**
```ruby
entity = Entity.find(1)
entity.update!(
  bedrock_knowledge_base_id: nil,
  bedrock_kb_status: nil,
  bedrock_last_ingestion_job_id: nil
)
```

#### Issue 2: "Ingestion job failed"

**Cause:** S3 permissions, empty bucket, or invalid data source

**Fix:**
1. Check S3 bucket permissions (KB needs read access)
2. Verify documents exist at: `s3://RAG_BUCKET/entities/ENTITY_ID/`
3. Check CloudWatch logs for detailed error messages

#### Issue 3: "No results from Bedrock KB"

**Cause:** Ingestion job not complete, or query doesn't match indexed content

**Fix:**
1. Wait for ingestion job to complete (check status)
2. Verify documents were indexed: check statistics in ingestion status
3. Try broader query terms

#### Issue 4: "AccessDeniedException"

**Cause:** IAM role missing required permissions

**Fix:**
1. Review IAM permissions (see Prerequisites section)
2. Ensure role has `bedrock:*` and `aoss:*` permissions
3. Check S3 bucket policy allows Bedrock access

## Cost Implications

### Bedrock Knowledge Base Costs

**OpenSearch Serverless:**
- $0.24/OCU-hour for indexing
- $0.24/OCU-hour for search
- Minimum 2 OCUs per collection
- **Estimate:** ~$350/month for small-medium workload

**Bedrock Retrieve API:**
- $0.10 per 1,000 search requests
- **Estimate:** $1.00 for 10,000 queries

**S3 Storage:**
- $0.023 per GB/month (Standard)
- **Estimate:** $0.23 for 10GB of documents

### Cost Optimization Tips

1. **Use Bedrock KB selectively**: Enable only for high-value entities
2. **Hybrid mode for small entities**: pgvector is free (uses PostgreSQL)
3. **Batch ingestion**: Trigger sync jobs during off-peak hours
4. **Monitor OCU usage**: Check AWS Cost Explorer

## Gradual Rollout Strategy

### Week 1: Internal Testing
- Enable Bedrock KB for 1 test entity
- Verify query results vs. pgvector baseline
- Monitor costs and performance

### Week 2: Pilot Customers
- Enable for 3-5 pilot entities
- Gather feedback on result quality
- Track cost per entity

### Week 3: Broader Rollout
- Enable for 25% of entities
- A/B test result quality
- Optimize ingestion frequency

### Week 4: Full Production
- Enable for all qualifying entities
- Set up automated cost alerts
- Document best practices

## Next Steps

After activating Phase 2:

1. **Phase 3: NLP Enhancement** - Add AWS Comprehend for entity extraction and sentiment analysis
2. **Phase 4: Infrastructure as Code** - Terraform for reproducible AWS resources
3. **Monitoring Dashboard** - Track RAG mode distribution and costs

## Support

For issues or questions about Phase 2:

1. Check logs: `docker compose logs web | grep -i bedrock`
2. Review Admin UI for entity-specific details
3. Test with Rails console scripts above
4. Check AWS CloudWatch for Bedrock KB logs

## Summary

Phase 2 gives you:
- ✅ **Fully managed RAG** - No vector DB to maintain
- ✅ **Intelligent fallback** - Auto-switches to best available backend
- ✅ **Per-entity control** - Enable KB for high-value customers only
- ✅ **Admin UI** - Easy KB creation and monitoring
- ✅ **Cost-effective** - Use pgvector for small entities, Bedrock KB for scale

**Next:** Enable for your first entity via `/admin/bedrock_kb` and start querying!
