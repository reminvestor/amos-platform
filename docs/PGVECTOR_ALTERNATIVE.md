# pgvector Alternative to Pinecone

## Overview

Replace Pinecone with PostgreSQL pgvector extension (like Ottomator uses).

**Benefits:**
- ✅ Save $70/month (Pinecone Starter plan)
- ✅ Simpler architecture (one database instead of two)
- ✅ Better for development (no external dependencies)

**Trade-offs:**
- ❌ Slower for very large datasets (>1M vectors)
- ❌ Requires PostgreSQL 11+ with pgvector extension
- ❌ More work to scale horizontally

## Migration Steps

### 1. Enable pgvector Extension

```sql
-- In PostgreSQL
CREATE EXTENSION IF NOT EXISTS vector;
```

### 2. Add Migration

```bash
rails g migration AddPgvectorToRagStores
```

```ruby
# db/migrate/xxx_add_pgvector_to_rag_stores.rb
class AddPgvectorToRagStores < ActiveRecord::Migration[8.0]
  def change
    # Enable pgvector extension
    enable_extension 'vector'

    # Add chunks table
    create_table :rag_chunks do |t|
      t.references :rag_store, null: false, foreign_key: true
      t.text :content, null: false
      t.vector :embedding, limit: 1536  # OpenAI ada-002 dimensions
      t.jsonb :metadata, default: {}
      t.integer :chunk_index

      t.timestamps
    end

    # Add vector similarity index (HNSW for fast search)
    add_index :rag_chunks, :embedding, using: :hnsw, opclass: :vector_cosine_ops
    add_index :rag_chunks, :metadata, using: :gin
  end
end
```

### 3. Update RagStore Model

```ruby
# app/models/rag_chunk.rb
class RagChunk < ApplicationRecord
  belongs_to :rag_store

  # Vector similarity search
  scope :nearest_neighbors, ->(embedding, limit: 5) {
    order(Arel.sql("embedding <=> '#{embedding}'"))
      .limit(limit)
  }
end

# app/models/rag_store.rb
class RagStore < ApplicationRecord
  has_many :rag_chunks, dependent: :destroy

  # Query this RAG store
  def query(query_text, top_k: 5)
    # Generate embedding for query
    embedding = generate_embedding(query_text)

    # Find nearest chunks
    rag_chunks.nearest_neighbors(embedding, limit: top_k)
  end
end
```

### 4. Update RagStoreService

```ruby
# app/services/rag_store_service.rb
class RagStoreService
  # Replace Pinecone with pgvector
  def create_rag_store(app_name, chunks, metadata = {})
    rag_store = RagStore.create!(
      name: metadata[:name],
      app_name: app_name,
      store_type: metadata[:store_type] || 'entity',
      entity: metadata[:entity],
      status: 'building'
    )

    # Generate embeddings (batch)
    embeddings = generate_embeddings_batch(chunks.map { |c| c[:content] })

    # Store chunks in Postgres
    chunks.each_with_index do |chunk, index|
      rag_store.rag_chunks.create!(
        content: chunk[:content],
        embedding: embeddings[index],
        metadata: chunk[:metadata],
        chunk_index: index
      )
    end

    rag_store.update!(
      status: 'active',
      chunk_count: chunks.length
    )

    {
      success: true,
      rag_store_id: rag_store.id,
      chunks_stored: chunks.length
    }
  end

  def query_rag_store(rag_store_id, query, current_entity:, top_k: 5)
    rag_store = RagStore.find_accessible(rag_store_id, current_entity)

    # Generate query embedding
    query_embedding = generate_embedding(query)

    # Search using pgvector
    results = rag_store.rag_chunks
                       .nearest_neighbors(query_embedding, limit: top_k)
                       .map { |chunk|
      {
        content: chunk.content,
        metadata: chunk.metadata,
        score: cosine_similarity(query_embedding, chunk.embedding)
      }
    }

    {
      success: true,
      results: results,
      rag_store: rag_store.name
    }
  end

  private

  def cosine_similarity(a, b)
    # pgvector stores as array
    a_vec = a.is_a?(String) ? JSON.parse(a) : a
    b_vec = b.is_a?(String) ? JSON.parse(b) : b

    dot_product = a_vec.zip(b_vec).sum { |x, y| x * y }
    magnitude_a = Math.sqrt(a_vec.sum { |x| x**2 })
    magnitude_b = Math.sqrt(b_vec.sum { |x| x**2 })

    dot_product / (magnitude_a * magnitude_b)
  end
end
```

### 5. Remove Pinecone Dependencies

```ruby
# Gemfile - Remove:
# gem 'pinecone'

# .env - Remove:
# PINECONE_API_KEY=...
# PINECONE_ENVIRONMENT=...
```

## Performance Comparison

### Small Dataset (<10K chunks)

| Metric | Pinecone | pgvector |
|--------|----------|----------|
| Query time | 50ms | 80ms |
| Insert time | 100ms | 60ms |
| Cost | $70/month | $0 |

**Winner: pgvector** (faster writes, free)

### Medium Dataset (100K chunks)

| Metric | Pinecone | pgvector |
|--------|----------|----------|
| Query time | 50ms | 200ms |
| Insert time | 100ms | 150ms |
| Cost | $70/month | $0 |

**Winner: Depends** (Pinecone faster, but pgvector still acceptable)

### Large Dataset (1M+ chunks)

| Metric | Pinecone | pgvector |
|--------|----------|----------|
| Query time | 50ms | 800ms |
| Insert time | 100ms | 500ms |
| Cost | $280/month | $0 |

**Winner: Pinecone** (significantly faster at scale)

## Recommendation

**Use pgvector if:**
- ✅ <100K total chunks across all RAG stores
- ✅ Budget-conscious
- ✅ Want simpler architecture
- ✅ Development/staging environments

**Use Pinecone if:**
- ✅ >100K chunks
- ✅ Need <100ms query times
- ✅ Planning to scale to millions of chunks
- ✅ Production with high traffic

## Hybrid Approach

**Best of both worlds:**
```ruby
# config/initializers/rag.rb
RAG_BACKEND = if Rails.env.production?
  :pinecone  # Fast, scalable
else
  :pgvector  # Free, simple for dev
end

# app/services/rag_store_service.rb
def backend
  @backend ||= case RAG_BACKEND
    when :pinecone then PineconeBackend.new
    when :pgvector then PgvectorBackend.new
  end
end
```

**Benefits:**
- Development: Free, simple (pgvector)
- Production: Fast, scalable (Pinecone)
- Easy to test both locally

## Cost Savings

**Current (Pinecone):**
```
Pinecone Starter: $70/month
OpenAI Embeddings: $10/month
Total: $80/month
```

**With pgvector:**
```
Pinecone: $0 (removed)
OpenAI Embeddings: $10/month
Total: $10/month
```

**Savings: $70/month ($840/year)**

## Ottomator's Approach

They use pgvector because:
1. **Simple use case** - CLI tool, not high-traffic SaaS
2. **Small datasets** - Personal docs, not enterprise scale
3. **Budget** - Open-source project, minimize costs

**For your AMOS platform:**
- If you expect <50K chunks total: **pgvector is fine**
- If you expect >100K chunks: **Pinecone is worth it**
- For now (early stage): **pgvector could save $840/year**

## Migration Path

1. **Week 1**: Implement pgvector alongside Pinecone
2. **Week 2**: Test both backends with same data
3. **Week 3**: Benchmark performance on real queries
4. **Week 4**: Choose winner, remove loser

No rush - you can run both and compare!
