# RAG Configuration: AWS & LocalStack Setup Guide

Complete guide for setting up Retrieval-Augmented Generation (RAG) in AMOS with AWS and LocalStack for local development.

## Quick Start

### Development (LocalStack)
```bash
# 1. Start LocalStack (Docker Compose)
docker compose up -d localstack

# 2. Configure .env for LocalStack
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
AWS_S3_ENDPOINT=http://localhost:4566
RAG_BUCKET=agent-marketing-rag-storage

# 3. Configure OpenAI (required for embeddings)
OPENAI_API_KEY=sk-your-key-here
OPENAI_EMBEDDING_MODEL=text-embedding-ada-002

# 4. Start Rails app
bin/dev
```

### Production (AWS)
```bash
# 1. Add AWS credentials to environment
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key

# 2. Remove LocalStack endpoint (use real AWS)
# AWS_S3_ENDPOINT=... (delete or comment out)

# 3. Ensure S3 bucket exists in your AWS account
aws s3 mb s3://agent-marketing-rag-storage --region us-east-1

# 4. Deploy with credentials configured
```

---

## Architecture Overview

AMOS RAG system consists of three components:

```
┌─────────────────────────────────────────────────┐
│  Document Upload (Scout Chat)                   │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│  Document Pipeline (Processing)                 │
│  - Extract text (PDF, DOCX, images)            │
│  - Create chunks (1000 tokens)                  │
│  - Generate embeddings (OpenAI)                 │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│  Vector Storage (PostgreSQL pgvector)           │
│  - Store embeddings                             │
│  - Store chunk metadata                         │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│  Semantic Search (RAG Query)                    │
│  - Generate query embedding                     │
│  - Find similar chunks (cosine similarity)      │
│  - Return relevant content to AI                │
└─────────────────────────────────────────────────┘
```

---

## Configuration Reference

### Required: AWS Bedrock

The system uses AWS Bedrock for Claude AI models:

```env
# AWS Region (defaults to us-east-1)
AWS_REGION=us-east-1

# AWS Credentials (for Bedrock access)
AWS_ACCESS_KEY_ID=your_access_key_id
AWS_SECRET_ACCESS_KEY=your_secret_access_key

# Bedrock Models
BEDROCK_DEFAULT_MODEL=claude-sonnet-4-5      # For most tasks
BEDROCK_CHAT_MODEL=claude-sonnet-4-5         # For Scout chat
BEDROCK_VOICE_MODEL=claude-3-haiku           # For voice (optional)
```

**LocalStack Note**: LocalStack doesn't emulate AWS Bedrock. You need real AWS credentials for Bedrock, even in development.

### Required: S3 Document Storage

RAG documents are stored in S3:

```env
# S3 bucket name
RAG_BUCKET=agent-marketing-rag-storage

# LocalStack only: Point to local emulation
AWS_S3_ENDPOINT=http://localhost:4566

# Production: Omit AWS_S3_ENDPOINT to use real S3
```

**Bucket Structure**:
```
s3://agent-marketing-rag-storage/
  entities/
    {entity_id}/
      raw_documents/
        document1.pdf
        document2.docx
      processed/
        document1.txt
        document2.txt
      embeddings/
        chunk_1.json
        chunk_2.json
```

**Creating S3 Bucket**:

LocalStack:
```bash
# Via Docker Compose (auto-created if configured)
# Or manually via awscli-local
awslocal s3 mb s3://agent-marketing-rag-storage
```

AWS:
```bash
aws s3 mb s3://agent-marketing-rag-storage --region us-east-1
```

### Required: OpenAI API (Embeddings)

RAG uses OpenAI for generating embeddings (NOT Bedrock):

```env
# OpenAI API Key (required for embeddings)
OPENAI_API_KEY=sk-your-key-here

# Embedding model (do NOT change)
OPENAI_EMBEDDING_MODEL=text-embedding-ada-002
```

**Why OpenAI?**
- Bedrock Titan embeddings: 1536 dimensions, no batch API
- OpenAI Ada-002: 1536 dimensions, batch API, much faster
- OpenAI is more cost-effective for high-volume embedding generation

**Cost**: ~$0.02 per 1 million tokens (~1000 documents)

### Required: PostgreSQL pgvector

Vector storage in PostgreSQL:

```env
# Database URL (standard Rails database)
DATABASE_URL=postgres://user:pass@localhost:5432/agent_marketing_development

# pgvector extension auto-installed in Docker
# Schema includes:
#   - rag_documents (chunks + embeddings)
#   - rag_stores (entity RAG stores)
#   - knowledge_documents (legacy)
#   - conversation_embeddings (search history)
```

**Capacity**:
- ~10M vectors before hitting performance limits
- pgvector is optimized for PostgreSQL
- Perfect for multi-tenant (per-entity) isolation

**LocalStack Note**: Use real PostgreSQL (not LocalStack), as LocalStack doesn't emulate RDS.

### Required: Redis (Optional but Recommended)

Embedding cache for faster repeated queries:

```env
# Redis URL for caching
REDIS_URL=redis://localhost:6379

# Enable embedding cache
RAG_EMBEDDING_CACHE_ENABLED=true

# Cache reduces API calls by ~70% for repeated queries
```

### Optional: Document Processing

Configure document extraction methods:

```env
# OCR Provider: 'textract' | 'docling' | 'auto'
OCR_PROVIDER=auto

# Use Docling for small documents (saves costs)
OCR_DOCLING_MAX_SIZE_MB=5

# Use Textract for form/invoice documents (better accuracy)
OCR_TEXTRACT_PREFERRED_TYPES=invoice,receipt,form,id

# Enable parallel processing for testing
OCR_SHADOW_MODE=false

# AWS Textract (only if OCR_PROVIDER includes 'textract')
TEXTRACT_ENABLED=true
TEXTRACT_SNS_TOPIC_ARN=
TEXTRACT_ROLE_ARN=
```

**Docling vs Textract**:
- **Docling**: Free, runs locally, handles general PDFs well, memory-intensive
- **Textract**: AWS service, handles scanned documents, forms better, costs money

### Optional: AWS Comprehend (NLP Enhancement)

Detect PII and classify documents:

```env
COMPREHEND_ENABLED=false
COMPREHEND_DETECT_PII=false
COMPREHEND_CLASSIFIER_ARN=
COMPREHEND_ROLE_ARN=
```

### Optional: Pinecone (Extreme Scale)

Only add if you have >10M document chunks:

```env
# Pinecone API key (leave commented unless needed)
# PINECONE_API_KEY=pcsk-your-key-here
# PINECONE_ENVIRONMENT=us-east-1-aws

# When to add Pinecone:
#   1. pgvector hitting performance limits
#   2. Need sub-10ms query latency at massive scale
#   3. Have millions of chunks across entities
```

**Cost**: ~$0.70/month per million vectors

### Optional: Bedrock Knowledge Base

Managed RAG (alternative to custom RAG):

```env
BEDROCK_KB_ENABLED=false
BEDROCK_KB_ID=
BEDROCK_KB_ROLE_ARN=
OPENSEARCH_COLLECTION_ARN=
OPENSEARCH_ENDPOINT=
```

**Note**: AMOS uses custom RAG with pgvector, not Bedrock Knowledge Base.

---

## RAG Configuration Settings

### Chunking Strategy

How documents are split into searchable pieces:

```env
# Strategy: 'semantic' (default) or 'simple'
RAG_CHUNKING_STRATEGY=semantic

# Chunk size (tokens for semantic, characters for simple)
RAG_CHUNK_SIZE=1000

# Overlap between chunks (characters, semantic only)
RAG_CHUNK_OVERLAP=200
```

**Strategies**:
- **Semantic**: Split at paragraph boundaries, better for semantic search
- **Simple**: Fixed-size chunks, predictable but may split sentences

### Embedding Configuration

```env
# Batch size for embedding generation (1-100)
RAG_EMBEDDING_BATCH_SIZE=100

# Cache embeddings to avoid re-generating
RAG_EMBEDDING_CACHE_ENABLED=true
```

**Performance**:
- Batch size 100: 0.5s per batch of 100 documents
- With cache: 70% fewer API calls
- Cost: ~$0.00002 per embedding

---

## Development Environment Setup

### Step 1: Start LocalStack

```bash
# compose.yaml includes localstack service
docker compose up -d localstack

# Wait for LocalStack to start (30-60 seconds)
docker compose logs localstack | grep "Ready"
```

### Step 2: Create S3 Bucket

```bash
# Using awscli-local (if installed)
awslocal s3 mb s3://agent-marketing-rag-storage

# Or use aws-cli with LocalStack endpoint
AWS_ACCESS_KEY_ID=test \
AWS_SECRET_ACCESS_KEY=test \
aws --endpoint-url=http://localhost:4566 \
  s3 mb s3://agent-marketing-rag-storage \
  --region us-east-1
```

### Step 3: Configure .env

```env
# AWS Configuration
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=test              # LocalStack uses 'test' credentials
AWS_SECRET_ACCESS_KEY=test
AWS_S3_ENDPOINT=http://localhost:4566  # Point to LocalStack

# RAG Storage
RAG_BUCKET=agent-marketing-rag-storage

# OpenAI (required - use real API key)
OPENAI_API_KEY=sk-your-real-key

# Bedrock Models (required - use real AWS credentials)
# Use your actual AWS credentials above for Bedrock access
BEDROCK_DEFAULT_MODEL=claude-sonnet-4-5
BEDROCK_CHAT_MODEL=claude-sonnet-4-5

# Redis (optional)
REDIS_URL=redis://localhost:6379

# RAG Settings
RAG_CHUNKING_STRATEGY=semantic
RAG_CHUNK_SIZE=1000
RAG_CHUNK_OVERLAP=200
RAG_EMBEDDING_CACHE_ENABLED=true
RAG_EMBEDDING_BATCH_SIZE=100

# Document Processing
OCR_PROVIDER=auto
OCR_DOCLING_MAX_SIZE_MB=5
DOCLING_ENABLED=true
```

### Step 4: Start Application

```bash
# This starts Rails server + asset compilation
bin/dev

# Or manually
rails server
```

### Step 5: Test RAG

```bash
# Via command
/test-rag

# Or manually
rails runner 'RagConfig.log_config'
```

---

## Production Environment Setup

### Step 1: Set Up AWS Resources

```bash
# 1. Create S3 bucket
aws s3 mb s3://agent-marketing-rag-storage \
  --region us-east-1

# 2. Enable versioning (optional, for recovery)
aws s3api put-bucket-versioning \
  --bucket agent-marketing-rag-storage \
  --versioning-configuration Status=Enabled

# 3. Set lifecycle policy (archive old documents)
aws s3api put-bucket-lifecycle-configuration \
  --bucket agent-marketing-rag-storage \
  --lifecycle-configuration file://lifecycle-policy.json
```

### Step 2: Configure IAM Permissions

Create IAM user for the application:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3RAGAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::agent-marketing-rag-storage",
        "arn:aws:s3:::agent-marketing-rag-storage/*"
      ]
    },
    {
      "Sid": "BedrockAccess",
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel"
      ],
      "Resource": "arn:aws:bedrock:*:*:foundation-model/*"
    },
    {
      "Sid": "TextractAccess",
      "Effect": "Allow",
      "Action": [
        "textract:StartDocumentAnalysis",
        "textract:GetDocumentAnalysis",
        "textract:AnalyzeDocument"
      ],
      "Resource": "*"
    }
  ]
}
```

### Step 3: Configure Environment Variables

```env
# AWS Credentials (use IAM user, not root)
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

# Do NOT set AWS_S3_ENDPOINT in production (uses real AWS)

# RAG Configuration
RAG_BUCKET=agent-marketing-rag-storage
RAG_CHUNKING_STRATEGY=semantic
RAG_CHUNK_SIZE=1000
RAG_EMBEDDING_CACHE_ENABLED=true

# OpenAI (required)
OPENAI_API_KEY=sk-your-production-key

# Bedrock Models
BEDROCK_DEFAULT_MODEL=claude-sonnet-4-5
BEDROCK_CHAT_MODEL=claude-sonnet-4-5

# Document Processing
OCR_PROVIDER=auto
TEXTRACT_ENABLED=true

# Database (RDS with pgvector)
DATABASE_URL=postgres://user:pass@rds-endpoint.rds.amazonaws.com:5432/amos_production

# Redis (ElastiCache)
REDIS_URL=redis://elasticache-endpoint.cache.amazonaws.com:6379
```

### Step 4: Deploy

```bash
# 1. Ensure all environment variables are set
# 2. Run migrations
rails db:migrate

# 3. Start application
# 4. Monitor CloudWatch logs
```

---

## Testing RAG Functionality

### Via Scout Chat

1. Open Scout chat in app
2. Upload a document (PDF, DOCX, TXT)
3. Write a message asking about the document
4. System automatically:
   - Extracts text from document
   - Creates chunks
   - Generates embeddings
   - Stores in RAG
   - Searches for relevant chunks
   - Includes in AI response

### Via Rails Console

```ruby
# 1. Create a test entity
entity = Entity.create!(name: 'Test')

# 2. Upload a document
file = File.read('test.pdf')
asset = entity.image_assets.create!(file: file)

# 3. Trigger RAG indexing
Rag::DocumentPipelineJob.perform_later(
  entity.rag_stores.first.id,
  '/path/to/file.pdf',
  { source: 'upload', asset_id: asset.id }
)

# 4. Check RAG documents
entity.rag_documents.count

# 5. Search
results = RagService.new(entity).search('question about document')
```

### Via Command

```bash
/test-rag
```

This runs comprehensive RAG tests:
- API validation
- Entity-scoped RAG stores
- Semantic search
- Multi-tenant isolation
- Performance metrics

---

## Troubleshooting

### "AWS credentials not found"

**LocalStack Development**:
```bash
# Ensure LocalStack is running
docker compose ps localstack

# Set dummy credentials in .env
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
AWS_S3_ENDPOINT=http://localhost:4566
```

**Production**:
```bash
# Check IAM user credentials
aws sts get-caller-identity

# Verify IAM permissions
aws s3 ls s3://agent-marketing-rag-storage
```

### "S3 bucket not found"

```bash
# LocalStack: Create bucket
awslocal s3 mb s3://agent-marketing-rag-storage

# AWS: Create bucket
aws s3 mb s3://agent-marketing-rag-storage --region us-east-1

# Verify
aws s3 ls (LocalStack: awslocal s3 ls)
```

### "OpenAI API errors"

```bash
# Check API key
echo $OPENAI_API_KEY

# Test connection
curl -H "Authorization: Bearer $OPENAI_API_KEY" \
  https://api.openai.com/v1/models

# Check rate limits
# Standard: 3500 RPM, 90000 TPM
# Upgrade in OpenAI dashboard if needed
```

### "Database errors (pgvector not installed)"

```bash
# Check pgvector extension
rails runner "ActiveRecord::Base.connection.execute('CREATE EXTENSION IF NOT EXISTS vector')"

# Or via Docker
docker compose exec web rails db:migrate

# Verify
rails runner "puts ActiveRecord::Base.connection.execute('SELECT extname FROM pg_extension').to_a"
```

### "Embedding generation timeout"

```bash
# Check OpenAI status
# Reduce batch size to lower memory usage
RAG_EMBEDDING_BATCH_SIZE=20

# Or disable embedding cache temporarily
RAG_EMBEDDING_CACHE_ENABLED=false
```

### "S3 access denied"

**LocalStack**:
```bash
# Verify credentials in .env
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test

# Check bucket exists and is accessible
awslocal s3 ls s3://agent-marketing-rag-storage
```

**AWS**:
```bash
# Verify IAM permissions
aws iam get-user

# Test S3 access
aws s3 ls s3://agent-marketing-rag-storage

# Check bucket policy allows your IAM user
aws s3api get-bucket-policy --bucket agent-marketing-rag-storage
```

---

## Performance Optimization

### Embedding Caching

With Redis enabled:

```env
REDIS_URL=redis://localhost:6379
RAG_EMBEDDING_CACHE_ENABLED=true
```

**Impact**:
- 70% reduction in OpenAI API calls
- 10x faster queries for repeated questions
- Cost reduction: ~$0.70/month per 10K queries

### Batch Processing

```env
RAG_EMBEDDING_BATCH_SIZE=100
```

Process multiple documents simultaneously:
- 100 documents: ~0.5s
- vs 1 at a time: ~5s

### Vector Search Optimization

PostgreSQL pgvector settings:

```sql
-- Check current configuration
SHOW shared_preload_libraries;

-- pgvector supports:
-- - L2 distance (default, fast)
-- - Cosine similarity (semantic)
-- - Inner product

-- Create index for fast search
CREATE INDEX ON rag_documents USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
```

---

## Monitoring & Debugging

### Check RAG Configuration

```bash
rails runner 'RagConfig.log_config'
```

Output:
```
📊 RAG Configuration:
  Chunking: semantic (size: 1000, overlap: 200)
  Embedding: text-embedding-ada-002 (batch: 100, cache: true)
```

### Monitor RAG Jobs

```bash
# Via SolidQueue (Rails 8 job processor)
rails jobs:work

# Check job status
rails runner 'SolidQueue::Job.where(job_class: "Rag::*").count'

# View recent jobs
SolidQueue::Job.order(created_at: :desc).limit(10)
```

### Check Vector Storage

```ruby
# Count stored vectors
entity.rag_documents.count

# View document chunks
entity.rag_documents.first(5).map { |d| { id: d.id, title: d.original_filename, chunks: d.chunks.count } }

# Check embedding dimension
entity.rag_documents.first.embedding&.length  # Should be 1536
```

### CloudWatch Logs (AWS)

```bash
# Monitor Bedrock invocations
aws logs tail /aws/bedrock/invocations --follow

# Monitor S3 access
aws logs tail /aws/s3/access-logs --follow

# Monitor Lambda (if using for document processing)
aws logs tail /aws/lambda/rag-document-processor --follow
```

---

## Cost Estimation

### Typical Usage (100 documents, 1000 queries/month)

| Component | Cost/Month | Notes |
|-----------|-----------|-------|
| S3 Storage | $0.02 | ~500MB for 100 documents |
| OpenAI Embeddings | $0.20 | ~1M tokens from embedding generation |
| Bedrock Claude | $5.00 | ~100K tokens from chat responses |
| PostgreSQL pgvector | $0.50 | On RDS micro instance |
| **Total** | **~$5.72** | Single entity with 100 docs |

### With Pinecone (10M+ vectors)

| Component | Cost/Month |
|-----------|-----------|
| pgvector (RDS) | $50.00 |
| Pinecone | $70.00 |
| OpenAI Embeddings | $20.00 |
| Bedrock Claude | $50.00 |
| **Total** | **~$190** |

---

## Scaling Considerations

### Single Tenant (One Entity)
- **Documents**: Up to 100,000
- **Storage**: pgvector handles 10M+ vectors
- **Latency**: <500ms for semantic search
- **Cost**: $5-20/month

### Multi-Tenant (Multiple Entities)
- Each entity has isolated RAG store
- pgvector efficiently handles entity scoping
- Add Pinecone at 10M+ vectors across all entities
- Cost scales linearly with document volume

### Migration Path
1. **Start**: LocalStack + pgvector
2. **Scale to AWS**: S3 + RDS + pgvector
3. **Extreme Scale**: Add Pinecone (optional)

---

## Related Documentation

- [RAG Testing Guide](./test-rag.md) - Run comprehensive RAG tests
- [Document Processing](./DOCUMENT_PROCESSING.md) - Text extraction details
- [Scout Chat Architecture](./SCOUT_ARCHITECTURE.md) - How RAG integrates with Chat
- [LocalStack Setup](./LOCALSTACK_SETUP.md) - Full LocalStack configuration
