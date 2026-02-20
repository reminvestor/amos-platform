# Vector Storage Strategy for AMOS RAG System

## Overview

AMOS uses a **pgvector-first** approach for vector storage, suitable for both local development and AWS production deployments. Pinecone integration is available as an optional enhancement for extreme scale.

## Architecture

### Primary Storage: pgvector (PostgreSQL Extension)

**What is pgvector?**
- PostgreSQL extension for storing and searching vector embeddings
- Provides fast similarity search using HNSW or IVFFlat indexes
- Native integration with PostgreSQL's ACID guarantees and multi-tenancy

**Why pgvector for Local + AWS?**
- ✅ **Simplicity**: No external service dependencies
- ✅ **Cost**: Included with PostgreSQL, no per-query pricing
- ✅ **Performance**: Handles 10M+ vectors efficiently with proper indexing
- ✅ **Multi-tenancy**: Native PostgreSQL row-level security
- ✅ **Consistency**: Transactional updates with document metadata
- ✅ **Backup**: Standard PostgreSQL backup/restore procedures
- ✅ **AWS RDS**: Fully supported with pgvector extension on RDS PostgreSQL

**Performance at Scale:**
- 100K vectors: <10ms query time
- 1M vectors: <50ms query time
- 10M vectors: <200ms query time (with IVFFlat index)
- Sufficient for 99% of production workloads

### Optional Enhancement: Pinecone

**When to Add Pinecone:**
- You have >10 million document chunks across all entities
- You need consistent sub-10ms query latency at extreme scale
- Your RDS database is hitting storage or performance limits
- You require global geo-distribution of vectors

**Pinecone Benefits:**
- ⚡ Ultra-low latency (<5ms) at any scale
- 📈 Unlimited horizontal scaling
- 🌍 Global distribution across regions
- 🔧 Managed service (no index tuning needed)

**Trade-offs:**
- 💰 Per-query pricing (vs pgvector's fixed cost)
- 🔌 External service dependency
- ⚙️ Additional API key management
- 🔄 Dual-write complexity

## Implementation Details

### Database Schema

```sql
-- pgvector extension enabled
CREATE EXTENSION IF NOT EXISTS vector;

-- rag_chunks table with vector column
CREATE TABLE rag_chunks (
  id bigint PRIMARY KEY,
  rag_document_id bigint NOT NULL,
  rag_store_id bigint NOT NULL,
  content text NOT NULL,
  embedding vector(1536),  -- pgvector column (Titan Embed dimensions)
  chunk_index integer,
  chunk_type varchar,
  metadata jsonb,
  pinecone_vector_id varchar,  -- Optional, NULL if Pinecone not used
  created_at timestamp,
  updated_at timestamp
);

-- Vector similarity index (IVFFlat for large datasets)
CREATE INDEX idx_rag_chunks_embedding
  ON rag_chunks
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);  -- Adjust lists based on dataset size

-- Full-text search index (hybrid search fallback)
CREATE INDEX idx_rag_chunks_content_fts
  ON rag_chunks
  USING gin (to_tsvector('english', content));

-- Entity isolation index
CREATE INDEX idx_rag_chunks_entity
  ON rag_chunks (rag_store_id);
```

### Query Pattern

```ruby
# Vector similarity search using pgvector
chunks = RagChunk
  .for_entity(entity)
  .where.not(embedding: nil)
  .nearest_neighbors(:embedding, query_embedding, distance: 'cosine')
  .limit(10)

# Hybrid search (70% vector, 30% keyword)
vector_results = RagChunk.nearest_neighbors(:embedding, query_embedding, distance: 'cosine').limit(10)
keyword_results = RagChunk.text_search(query_text).limit(5)
merged_results = merge_and_rerank(vector_results, keyword_results)
```

### Embedding Pipeline

1. **Document Upload** → `DocumentPipelineJob`
2. **Docling Processing** → `DoclingExtractionJob` (extracts text, tables, structure)
3. **Chunking** → `ChunkingJob` (creates semantic chunks)
4. **Embedding Generation** → `EmbeddingBatchJob`
   - Generates embeddings via AWS Bedrock (Titan Embed)
   - Stores in PostgreSQL pgvector column
   - Optionally stores in Pinecone if configured

### Dual-Write Strategy (when Pinecone enabled)

```ruby
# In EmbeddingBatchJob
def perform(chunk_ids)
  chunks = RagChunk.find(chunk_ids)
  embeddings = generate_embeddings(chunks)  # AWS Bedrock

  # Primary write: pgvector (always)
  update_chunks_with_embeddings(chunks, embeddings)

  # Secondary write: Pinecone (optional)
  store_in_pinecone(chunks, rag_store) if pinecone_configured?
end

def pinecone_configured?
  ENV['PINECONE_API_KEY'].present? && ENV['PINECONE_ENVIRONMENT'].present?
end
```

## Deployment Configuration

### Local Development

**compose.yaml:**
```yaml
services:
  db:
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_DB: amos_development
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    volumes:
      - postgres-data:/var/lib/postgresql/data
```

**No additional configuration needed!** pgvector works out of the box.

### AWS RDS PostgreSQL

**Terraform Configuration:**
```hcl
# RDS instance with pgvector
resource "aws_db_instance" "amos_postgres" {
  engine         = "postgres"
  engine_version = "16.3"  # pgvector supported in PG 14+
  instance_class = "db.t3.medium"

  parameter_group_name = aws_db_parameter_group.pgvector.name
}

# Custom parameter group with pgvector
resource "aws_db_parameter_group" "pgvector" {
  family = "postgres16"

  parameter {
    name  = "shared_preload_libraries"
    value = "pgvector"
  }

  # Optimize for vector operations
  parameter {
    name  = "maintenance_work_mem"
    value = "2GB"  # Faster index building
  }

  parameter {
    name  = "effective_cache_size"
    value = "12GB"  # Improves query planning
  }
}
```

**Enabling pgvector:**
```sql
-- Run once after RDS instance creation
CREATE EXTENSION IF NOT EXISTS vector;

-- Verify installation
SELECT * FROM pg_extension WHERE extname = 'vector';
```

### Adding Pinecone (Optional)

**1. Set Environment Variables:**
```bash
export PINECONE_API_KEY=pcsk-your-key-here
export PINECONE_ENVIRONMENT=us-east-1-aws
```

**2. Create Pinecone Index:**
```ruby
# Rails console or rake task
require 'pinecone'

Pinecone::Index.create(
  name: 'amos-rag-production',
  dimension: 1536,  # Titan Embed dimensions
  metric: 'cosine',
  spec: {
    serverless: {
      cloud: 'aws',
      region: 'us-east-1'
    }
  }
)
```

**3. Update RagStore Records:**
```ruby
# Add Pinecone index info to existing stores
RagStore.find_each do |store|
  store.update!(
    pinecone_index: 'amos-rag-production',
    pinecone_namespace: "entity_#{store.entity_id}"
  )
end
```

**4. Backfill Existing Embeddings:**
```ruby
# Re-run embedding jobs to populate Pinecone
RagChunk.where.not(embedding: nil).where(pinecone_vector_id: nil).find_in_batches(batch_size: 100) do |batch|
  Rag::EmbeddingBatchJob.perform_later(batch.map(&:id))
end
```

## Migration Path

### Phase 1: Local Development (Current)
- Use pgvector only
- No Pinecone configuration needed
- Sufficient for development and testing

### Phase 2: AWS Production (Recommended)
- Use AWS RDS PostgreSQL with pgvector
- Handles production workloads up to 10M vectors
- No additional services required

### Phase 3: Extreme Scale (Optional)
- Add Pinecone for >10M vectors or <10ms latency requirements
- Enable dual-write by setting `PINECONE_API_KEY`
- Gradual rollout per entity or document type

## Monitoring and Optimization

### pgvector Performance Tuning

**Index Selection:**
```sql
-- For datasets <1M vectors: HNSW (better accuracy)
CREATE INDEX idx_rag_chunks_embedding_hnsw
  ON rag_chunks
  USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

-- For datasets >1M vectors: IVFFlat (faster queries)
CREATE INDEX idx_rag_chunks_embedding_ivfflat
  ON rag_chunks
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 1000);  -- sqrt(row_count) is a good starting point
```

**Query Monitoring:**
```sql
-- Check slow queries
SELECT
  query,
  mean_exec_time,
  calls
FROM pg_stat_statements
WHERE query LIKE '%nearest_neighbors%'
ORDER BY mean_exec_time DESC
LIMIT 10;

-- Index usage stats
SELECT
  schemaname,
  tablename,
  indexname,
  idx_scan,
  idx_tup_read
FROM pg_stat_user_indexes
WHERE tablename = 'rag_chunks';
```

### Cache Hit Rate Monitoring

```ruby
# In Rails console
entity = Entity.first
rag_stores = entity.rag_stores

# Cache hit rate per store
rag_stores.each do |store|
  hit_rate = store.cache_hit_rate
  avg_time = store.avg_response_time

  puts "Store: #{store.name}"
  puts "  Cache Hit Rate: #{hit_rate}%"
  puts "  Avg Response Time: #{avg_time}ms"
end
```

## Cost Analysis

### pgvector (AWS RDS)

**Example: db.t3.medium (2 vCPU, 4GB RAM)**
- Monthly Cost: ~$62/month (on-demand)
- Storage: $0.115/GB-month for gp3
- Backup: $0.095/GB-month

**Total for 100GB database:** ~$74/month

### Pinecone (for comparison)

**Serverless Pricing:**
- Storage: $0.28 per 1M vectors per month
- Queries: $0.045 per 1M queries

**Example: 10M vectors, 1M queries/month**
- Storage: $2.80/month
- Queries: $0.045/month
- **Total:** ~$3/month

**Note:** Pinecone becomes cost-effective at scale, but requires external dependency management.

## Recommendations

### For Most Deployments: ✅ pgvector Only
- Simpler architecture
- Lower operational complexity
- Predictable costs
- Excellent performance for typical workloads

### Add Pinecone Only If:
- ❗ You exceed 10M vectors
- ❗ You need <10ms p99 latency
- ❗ You have budget for dual-write complexity

## Testing

### Verify pgvector Installation

```bash
# Via Rails runner
docker compose exec web rails runner "
  result = ActiveRecord::Base.connection.execute(\"SELECT extname FROM pg_extension WHERE extname = 'vector'\")
  puts result.to_a.any? ? '✅ pgvector installed' : '❌ pgvector missing'
"
```

### Test Vector Search

```ruby
# In Rails console
entity = Entity.first
service = HybridRagQueryService.new(entity)

# Query should work without Pinecone
results = service.query('test query', top_k: 5)
puts "Found #{results[:chunks].length} chunks"
puts "Response time: #{results[:response_time_ms]}ms"
```

### Benchmark Performance

```ruby
# Benchmark vector search performance
require 'benchmark'

entity = Entity.first
query_embedding = Array.new(1536) { rand }

time = Benchmark.measure {
  results = RagChunk
    .for_entity(entity)
    .nearest_neighbors(:embedding, query_embedding, distance: 'cosine')
    .limit(10)
    .to_a
}

puts "Query time: #{(time.real * 1000).to_i}ms for #{RagChunk.count} total chunks"
```

## References

- **pgvector GitHub**: https://github.com/pgvector/pgvector
- **pgvector Docs**: https://github.com/pgvector/pgvector#getting-started
- **neighbor gem** (Rails integration): https://github.com/ankane/neighbor
- **AWS RDS PostgreSQL**: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html
- **Pinecone Docs**: https://docs.pinecone.io/
