# Hybrid RAG Implementation Complete

## Overview

This document describes the **completed hybrid RAG implementation** that combines **pgvector (PostgreSQL)** and **Pinecone** for production-scale vector search with local development capabilities.

> **Status**: ✅ Implementation Complete (Tests & Full Integration Pending)
> **Date**: October 26, 2024
> **Architecture**: Dual-write strategy (pgvector + Pinecone)

---

## Why Both pgvector AND Pinecone?

### The Hybrid Approach

Instead of choosing one or the other, we use **both** for different purposes:

| Storage | Purpose | When It's Used |
|---------|---------|----------------|
| **pgvector** | Local development, keyword fallback, hybrid search | Development, testing, keyword queries |
| **Pinecone** | Production vector search, scalability | Production queries, high-volume scenarios |

### Benefits

1. **Development without Pinecone costs**: Run full RAG pipeline locally
2. **Hybrid search**: Combine vector similarity (pgvector/Pinecone) + keyword search (PostgreSQL FTS)
3. **Redundancy**: If Pinecone fails, pgvector provides fallback
4. **Testing**: Unit tests don't require external API calls

---

## Architecture

### Storage Tiers

```
┌─────────────────────────────────────────────────────────────┐
│                     Document Upload                          │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │ DocumentPipelineJob   │
         │ - Upload to S3        │
         │ - Create RagDocument  │
         └───────────┬───────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │ DoclingExtractionJob  │
         │ - Process with Docling│
         │ - Extract structure   │
         │ - Store JSON in S3    │
         └───────────┬───────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │   ChunkingJob         │
         │ - Smart chunking      │
         │ - Create RagChunks    │
         └───────────┬───────────┘
                     │
                     ▼
         ┌───────────────────────────────────┐
         │   EmbeddingBatchJob               │
         │ - Generate embeddings (Bedrock)   │
         │ - Store in PostgreSQL (pgvector)  │
         │ - Store in Pinecone (production)  │
         └───────────────────────────────────┘
```

### Query Flow

```
User Query
    │
    ▼
┌────────────────────────────────┐
│ HybridRagQueryService          │
│                                 │
│ 1. Generate query embedding    │
│    (Bedrock Titan)             │
│                                 │
│ 2. Vector Search (pgvector)    │
│    - Entity chunks (70%)       │
│    - System chunks (30%)       │
│                                 │
│ 3. Vector Search (Pinecone)    │
│    - If configured             │
│                                 │
│ 4. Keyword Search (PostgreSQL) │
│    - Full-text search          │
│    - GIN indexes               │
│                                 │
│ 5. Merge & Rerank Results      │
│    - Deduplicate               │
│    - Score: 70% vector + 30% keyword │
│                                 │
│ 6. Cache in Redis (1 hour)     │
└────────────────────────────────┘
    │
    ▼
Context returned to user/Claude
```

---

## Implementation Details

### 1. SolidQueue Configuration

**File**: `config/queue.yml`

```yaml
# RAG Processing Queues (Priority Order)
workers:
  - queues: critical      # Real-time user operations (5 threads)
  - queues: embeddings    # API-rate limited (3 threads)
  - queues: docling       # Memory-intensive (2 threads)
  - queues: documents     # General processing (3 threads)
  - queues: default       # Everything else (3 threads)
  - queues: maintenance   # Cleanup tasks (1 thread)
```

**Environment Variables**:
- `EMBEDDING_WORKERS`: Number of embedding worker processes (default: 1)
- `DOCLING_WORKERS`: Number of docling worker processes (default: 1)

---

### 2. Job Workers

#### A. DocumentPipelineJob
**Queue**: `documents`
**Purpose**: Entry point for document upload

**Flow**:
1. Validate file exists
2. Calculate SHA256 hash (deduplication)
3. Upload to S3 (`entities/{entity_id}/raw_documents/`)
4. Create `RagDocument` record
5. Queue `DoclingExtractionJob`

**File**: `app/jobs/rag/document_pipeline_job.rb`

---

#### B. DoclingExtractionJob
**Queue**: `docling` (memory-intensive)
**Purpose**: Extract document structure using Docling

**Flow**:
1. Download document from S3
2. Check if Docling available (`DoclingBridgeService.available?`)
3. Run Docling CLI with timeout (10 minutes)
4. Store JSON output in S3
5. Update `RagDocument` metadata
6. Queue `ChunkingJob`

**Fallback**: If Docling fails, queues `FallbackProcessorJob` instead

**File**: `app/jobs/rag/docling_extraction_job.rb`

---

#### C. FallbackProcessorJob
**Queue**: `documents`
**Purpose**: Simple text extraction when Docling unavailable

**Supported Formats**:
- **PDF**: `pdf-reader` gem
- **DOCX**: `docx` gem
- **HTML**: `nokogiri` gem
- **Plain text**: Direct file read

**Chunking**: Simple sliding window (1000 chars, 100 char overlap)

**File**: `app/jobs/rag/fallback_processor_job.rb`

---

#### D. ChunkingJob
**Queue**: `documents`
**Purpose**: Intelligent chunking using `DoclingChunkingService`

**Features**:
- Section-aware chunking (preserves document structure)
- Table extraction as separate chunks
- Code block handling
- Token-aware splitting (512 tokens max)
- Overlapping chunks for context (50 tokens)

**Output**: Creates `RagChunk` records in PostgreSQL

**File**: `app/jobs/rag/chunking_job.rb`

---

#### E. EmbeddingBatchJob
**Queue**: `embeddings` (rate-limited)
**Purpose**: **DUAL-WRITE** to pgvector AND Pinecone

**Flow**:
1. Generate embeddings via **AWS Bedrock** (Titan Embed)
2. **Store in PostgreSQL** (pgvector column)
3. **Store in Pinecone** (if configured)
4. Check if all chunks embedded → mark `RagStore` as "ready"

**Batch Size**: 10 chunks per job
**Retries**: 5 attempts with exponential backoff
**Throttling**: Respects Bedrock API rate limits

**File**: `app/jobs/rag/embedding_batch_job.rb`

---

### 3. Services

#### HybridRagQueryService
**Purpose**: Intelligent retrieval using both pgvector and Pinecone

**Search Strategy**:
1. **Vector Search (pgvector)**:
   - Entity chunks (nearest neighbors, cosine distance)
   - System chunks (if `include_system: true`)
2. **Vector Search (Pinecone)** (if configured)
3. **Keyword Search (PostgreSQL FTS)**:
   - Full-text search using GIN indexes
   - Fallback for queries that don't match vectors well
4. **Merge & Rerank**:
   - Deduplicate by chunk ID
   - Weighted score: `70% vector + 30% keyword`
5. **Cache Results** (Redis, 1 hour TTL)

**File**: `app/services/hybrid_rag_query_service.rb`

**Usage**:
```ruby
service = HybridRagQueryService.new(entity)

# Just retrieval
result = service.query("How do I create a campaign?", top_k: 10)

# With Claude response
result = service.query_with_claude("How do I create a campaign?")
```

---

#### DoclingChunkingService
**Purpose**: Smart document chunking based on structure

**Features**:
- **Section-based chunking**: Preserves headings and hierarchy
- **Table handling**: Converts to markdown, stores as separate chunks
- **Code blocks**: Preserves syntax highlighting info
- **Sliding window fallback**: For plain text or large sections
- **Token estimation**: ~4 chars per token heuristic

**File**: `app/services/docling_chunking_service.rb`

---

#### RagStoreService (Enhanced)
**New Methods**:

```ruby
service = RagStoreService.new

# Upload document via job pipeline
service.upload_document(
  '/path/to/file.pdf',
  entity: current_entity,
  user: current_user,
  store_type: 'entity'
)
# => { success: true, rag_store_id: 123, status: 'processing' }

# Hybrid query (pgvector + Pinecone)
service.hybrid_query(entity, "How do I...?")

# Hybrid query with Claude response
service.hybrid_query_with_claude(entity, "How do I...?")
```

**File**: `app/services/rag_store_service.rb`

---

### 4. Database Schema

#### New Tables (from migration `20251025165018_enhance_rag_storage.rb`):

**rag_documents**:
- `rag_store_id` (foreign key)
- `original_filename`
- `file_hash` (SHA256, for deduplication)
- `docling_metadata` (JSONB)
- `extracted_tables` (JSONB array)
- `page_count`

**rag_chunks**:
- `rag_document_id` (foreign key)
- `content` (text)
- **`embedding` (vector(1536))** ← pgvector column
- `pinecone_vector_id` (string)
- `metadata` (JSONB: page, section, etc.)
- `chunk_index`, `chunk_type`, `token_count`

**Indexes**:
- **pgvector IVFFlat**: `index_rag_chunks_on_embedding` (cosine distance)
- **PostgreSQL GIN**: Full-text search on `content`

**rag_queries**:
- Tracks query performance, cache hits, response times
- `chunks_retrieved_count`, `relevance_scores` (JSONB)

**rag_processing_jobs**:
- Tracks job lifecycle (pending, processing, completed, failed)
- `job_id` (SolidQueue JID), `job_type`, `error_message`

---

### 5. S3 Storage Structure

**Bucket**: `RAG_BUCKET` environment variable

```
s3://amos-rag-storage/
├── entities/
│   └── {entity_id}/
│       ├── raw_documents/
│       │   └── {rag_store_id}/
│       │       └── {timestamp}_{filename}.pdf
│       ├── docling_output/
│       │   └── {rag_store_id}/
│       │       └── {rag_document_id}_output.json
│       └── processed/
│           └── {rag_store_id}/
│               └── chunks.json
└── system/
    └── amos/
        ├── raw_documents/
        └── docling_output/
```

**Encryption**: Server-side AES256
**Lifecycle** (configured in Terraform):
- Entity docs: → INTELLIGENT_TIERING after 90 days
- System docs: Retained forever
- Temp files: Auto-delete after 7 days

---

## Usage Guide

### Uploading a Document

```ruby
# Via RagStoreService
service = RagStoreService.new

result = service.upload_document(
  '/tmp/user_guide.pdf',
  entity: current_entity,
  user: current_user,
  name: 'User Guide',
  store_type: 'entity'
)

# => { success: true, rag_store_id: 123, status: 'processing' }

# Check status
rag_store = RagStore.find(result[:rag_store_id])
rag_store.processing_stats
# => {
#   total_documents: 1,
#   total_chunks: 42,
#   embedded_chunks: 42,
#   pending_chunks: 0,
#   processing_jobs: { completed: 4, failed: 0 }
# }
```

---

### Querying Documents

```ruby
# Hybrid query (pgvector + Pinecone + keyword)
service = RagStoreService.new

result = service.hybrid_query(
  current_entity,
  "How do I create a drip campaign?",
  top_k: 10,
  include_system: true
)

# => {
#   query: "How do I create a drip campaign?",
#   chunks: [
#     {
#       id: 123,
#       content: "...",
#       similarity_score: 0.92,
#       source: :pgvector,
#       metadata: { filename: "User Guide.pdf", page: 42 }
#     },
#     ...
#   ],
#   context: "...", # Formatted for Claude
#   response_time_ms: 150,
#   source_count: 10
# }

# Query with Claude response
result = service.hybrid_query_with_claude(
  current_entity,
  "How do I create a drip campaign?"
)

# => { ..., claude_response: "To create a drip campaign..." }
```

---

### Monitoring

```ruby
# Check RAG store status
rag_store.status  # => "ready" | "processing" | "failed"
rag_store.all_chunks_embedded?  # => true/false

# Processing statistics
rag_store.processing_stats
# => {
#   total_documents: 3,
#   total_chunks: 156,
#   embedded_chunks: 156,
#   pending_chunks: 0,
#   processing_jobs: {
#     pending: 0,
#     processing: 0,
#     completed: 12,
#     failed: 0
#   }
# }

# Access tracking
rag_store.access_count  # => 42
rag_store.last_accessed_at  # => 2024-10-26 10:30:00 UTC

# Query analytics
RagQuery.where(entity: current_entity)
        .where('created_at > ?', 7.days.ago)
        .average(:response_time_ms)  # => 125.5

# Cache hit rate
entity.rag_queries
      .where('created_at > ?', 1.day.ago)
      .where(cache_hit: true)
      .count / entity.rag_queries.where('created_at > ?', 1.day.ago).count.to_f
# => 0.42 (42% cache hit rate)
```

---

## Testing

### Test Files Needed

**Unit Tests**:
- `test/jobs/rag/document_pipeline_job_test.rb`
- `test/jobs/rag/docling_extraction_job_test.rb`
- `test/jobs/rag/chunking_job_test.rb`
- `test/jobs/rag/embedding_batch_job_test.rb`
- `test/jobs/rag/fallback_processor_job_test.rb`
- `test/services/hybrid_rag_query_service_test.rb`
- `test/services/docling_chunking_service_test.rb`

**Integration Tests**:
- `test/integration/hybrid_rag_pipeline_test.rb`

### Testing Strategy

**Unit Tests**:
- Mock S3, Bedrock, Pinecone API calls
- Use test fixtures for documents and chunks
- Verify job chaining (DocumentPipeline → Docling → Chunking → Embedding)

**Integration Tests**:
- End-to-end: Upload PDF → Extract → Chunk → Embed → Query
- Test both pgvector and Pinecone paths
- Verify hybrid search merging

---

## Configuration

### Environment Variables

```bash
# AWS
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=xxx
AWS_SECRET_ACCESS_KEY=xxx
RAG_BUCKET=amos-rag-storage  # Separate from AWS_S3_BUCKET

# Pinecone (optional for local dev)
PINECONE_API_KEY=xxx
PINECONE_ENVIRONMENT=us-east-1-aws

# SolidQueue Workers
JOB_CONCURRENCY=1
EMBEDDING_WORKERS=1
DOCLING_WORKERS=1

# Redis (for caching)
REDIS_URL=redis://localhost:6379/0
```

---

## Deployment Checklist

- [x] Database migration applied (`rails db:migrate`)
- [x] pgvector extension enabled in PostgreSQL
- [ ] SolidQueue workers running (`bin/jobs`)
- [ ] S3 bucket created with lifecycle policies
- [ ] Terraform RDS changes applied (pgvector parameter group)
- [ ] Environment variables configured
- [ ] Docling Python library installed (optional, fallback exists)

---

## Performance Considerations

### Indexing
- **pgvector**: IVFFlat index for O(log n) similarity search
- **PostgreSQL**: GIN index for full-text search
- **Pinecone**: Built-in HNSW indexing

### Caching
- **Query results**: Redis cache (1 hour TTL)
- **Embedding cache**: `EmbeddingCacheService` (if enabled)

### Scaling
- **Horizontal**: Add more SolidQueue worker processes
- **Vertical**: Increase `threads` per worker in `queue.yml`
- **Queue isolation**: Separate workers for docling, embeddings, documents

---

## Cost Optimization

### S3 Storage
- **INTELLIGENT_TIERING**: Auto-moves to cheaper tiers after 90 days
- **Lifecycle rules**: Delete temp files after 7 days
- **Compression**: Docling JSON outputs are compressed

### Bedrock Embeddings
- **Batch processing**: 10 chunks per job
- **Caching**: Avoid re-embedding duplicate content
- **Titan Embed**: $0.0001 per 1K tokens (cheap!)

### Pinecone
- **Optional in dev**: Use only pgvector locally
- **Namespace consolidation**: One namespace per RAG store
- **Archival**: Move old vectors out of hot storage

---

## Future Enhancements

### Planned
- [ ] Automated archival job (move >60 day old docs to Glacier)
- [ ] Admin dashboard for RAG monitoring
- [ ] Query result reranking (cross-encoder model)
- [ ] Multi-modal support (images, audio transcripts)

### Ideas
- [ ] Incremental document updates (detect changes, re-chunk only diffs)
- [ ] Query expansion (synonyms, paraphrasing)
- [ ] Personalized ranking (user feedback loop)

---

## Troubleshooting

### Issue: Documents stuck in "processing"

**Check**:
1. SolidQueue workers running? `bin/jobs` or `docker compose logs web`
2. Check failed jobs: `RagProcessingJob.where(status: :failed)`
3. Review error messages: `RagProcessingJob.last.error_message`

**Fix**:
```ruby
# Reprocess failed document
rag_store = RagStore.find(123)
rag_store.rag_documents.each do |doc|
  Rag::DoclingExtractionJob.perform_later(doc.id)
end
```

---

### Issue: Embeddings not being generated

**Check**:
1. Bedrock credentials configured? `ENV['AWS_ACCESS_KEY_ID']`
2. Check embedding queue: `SolidQueue::Job.where(queue_name: 'embeddings')`
3. Review Bedrock errors in logs

**Fix**:
```ruby
# Manually queue embedding jobs for pending chunks
rag_store.rag_chunks.where(embedding: nil).in_groups_of(10, false).each do |batch|
  Rag::EmbeddingBatchJob.perform_later(batch.map(&:id))
end
```

---

### Issue: Queries returning no results

**Check**:
1. Are chunks embedded? `rag_store.all_chunks_embedded?`
2. Is pgvector index created? Check schema for `index_rag_chunks_on_embedding`
3. Try keyword search: `RagChunk.text_search("campaign")`

**Fix**:
```ruby
# Rebuild pgvector index (if needed)
ActiveRecord::Base.connection.execute(
  "REINDEX INDEX index_rag_chunks_on_embedding;"
)
```

---

## Summary

✅ **Implementation Complete**:
- 5 job workers (DocumentPipeline, Docling, Chunking, Embedding, Fallback)
- 2 core services (HybridRagQuery, DoclingChunking)
- Dual-write strategy (pgvector + Pinecone)
- SolidQueue configuration with priority queues
- State management in RagStore model

🚧 **Next Steps**:
- Write comprehensive unit tests
- Integration testing end-to-end
- Production deployment & monitoring

---

**Questions or issues?** Check `docs/architecture/rag-storage.md` for detailed architecture diagrams.
