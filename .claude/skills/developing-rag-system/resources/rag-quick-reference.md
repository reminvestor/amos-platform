# RAG System Quick Reference

Quick reference for common RAG operations in the AMOS codebase.

## Table of Contents
- [Database Queries](#database-queries)
- [Creating RAG Stores](#creating-rag-stores)
- [Querying RAG](#querying-rag)
- [Access Control](#access-control)
- [Pinecone Operations](#pinecone-operations)
- [Document Processing](#document-processing)
- [Debugging](#debugging)

## Database Queries

### List All RAG Stores
```ruby
# All stores
RagStore.all

# System stores (shared across entities)
RagStore.where(store_type: 'system')

# Entity stores (customer-specific)
RagStore.where(store_type: 'entity')

# Active stores only
RagStore.where(status: 'active')
```

### Entity-Scoped Queries
```ruby
entity = Entity.find(1)

# All stores accessible to entity
RagStore.accessible_by(entity)

# Entity's own RAG stores
RagStore.where(entity: entity)

# Count by type
RagStore.accessible_by(entity).group(:store_type).count
```

### Search by Name or App
```ruby
# Find by name
RagStore.where("name LIKE ?", "%Brand%")

# Find by app_name
RagStore.where(app_name: "AMOS")

# Combined
RagStore.where(app_name: "AMOS", status: "active")
```

## Creating RAG Stores

### System RAG Store (Shared)
```ruby
service = RagStoreService.new

chunks = [
  { content: "AMOS is a conversational AI platform", metadata: { source: "amos.md" } },
  { content: "Scout is the AI assistant", metadata: { source: "scout.md" } }
]

result = service.create_rag_store(
  "AMOS Documentation",
  chunks,
  {
    store_type: 'system',
    app_name: 'AMOS',
    entity: nil,  # No entity for system stores
    user: nil
  }
)

puts result[:success]  # => true
puts result[:rag_store].id
```

### Entity RAG Store (Customer-Specific)
```ruby
entity = Entity.find(1)
user = entity.users.first
service = RagStoreService.new

chunks = [
  { content: "Our brand colors are blue (#0066CC) and white", metadata: { source: "brand.pdf" } }
]

result = service.create_rag_store(
  "Brand Guidelines",
  chunks,
  {
    store_type: 'entity',
    app_name: 'Custom',
    entity: entity,      # Required for entity stores
    user: user,
    metadata: {
      uploaded_at: Time.current,
      file_name: "brand_guidelines.pdf"
    }
  }
)

puts result[:success]  # => true
puts result[:rag_store].pinecone_namespace
```

### From Uploaded File
```ruby
entity = Entity.find(1)
user = entity.users.first

# Process document
processor = DocumentProcessorService.new
doc_result = processor.process_documents([{
  content: File.read('path/to/document.pdf'),
  filename: 'document.pdf',
  mime_type: 'application/pdf'
}])

# Create RAG store
if doc_result[:success]
  service = RagStoreService.new
  rag_result = service.create_rag_store(
    "My Document",
    doc_result[:chunks],
    { entity: entity, user: user, store_type: 'entity' }
  )
end
```

## Querying RAG

### Basic Query
```ruby
entity = Entity.find(1)
store = RagStore.accessible_by(entity).first

service = RagStoreService.new
result = service.query_rag_store(
  store.id,
  "What are our brand colors?",
  current_entity: entity,
  top_k: 5
)

result[:chunks].each do |chunk|
  puts "Score: #{chunk[:score]}"
  puts "Content: #{chunk[:content]}"
  puts "Source: #{chunk[:metadata][:source]}"
  puts "---"
end
```

### Query Multiple Stores
```ruby
entity = Entity.find(1)
query = "product features"

# Get all entity stores
stores = RagStore.accessible_by(entity)
                 .where(store_type: 'entity', status: 'active')

service = RagStoreService.new

# Query each store
all_results = stores.flat_map do |store|
  result = service.query_rag_store(
    store.id,
    query,
    current_entity: entity,
    top_k: 3
  )
  result[:chunks]
end

# Sort by relevance
top_results = all_results.sort_by { |c| -c[:score] }.first(10)
```

### Query with Filters
```ruby
# Query only specific app
stores = RagStore.accessible_by(entity)
                 .where(app_name: "AMOS", status: "active")

# Query by name pattern
stores = RagStore.accessible_by(entity)
                 .where("name LIKE ?", "%Brand%")
```

## Access Control

### Check Access
```ruby
entity = Entity.find(1)
store = RagStore.find(5)

# Check if entity can access
if store.accessible_by?(entity)
  puts "✅ Access granted"
else
  puts "❌ Access denied"
end
```

### Safe Find (Access-Controlled)
```ruby
entity = Entity.find(1)

# Raises RecordNotFound if access denied
begin
  store = RagStore.find_accessible(5, entity)
  puts "✅ Store: #{store.name}"
rescue ActiveRecord::RecordNotFound
  puts "❌ Store not found or access denied"
end
```

### Scope All Queries by Entity
```ruby
entity = Entity.find(1)

# ALWAYS use accessible_by() for queries
RagStore.accessible_by(entity)  # Returns system stores + entity's own stores

# NEVER use direct queries (security risk!)
# BAD:  RagStore.find(id)
# BAD:  RagStore.where(entity: entity)
# GOOD: RagStore.accessible_by(entity)
```

## Pinecone Operations

### Get Vector Stats
```ruby
store = RagStore.find(1)

client = Pinecone::Client.new(api_key: ENV['PINECONE_API_KEY'])
index = client.index(store.pinecone_index)

stats = index.describe_index_stats(namespace: store.pinecone_namespace)
vector_count = stats['namespaces'][store.pinecone_namespace]['vector_count']

puts "Vectors: #{vector_count}"
```

### Query Pinecone Directly
```ruby
store = RagStore.find(1)

# Generate query embedding
openai = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
embedding_result = openai.embeddings(
  parameters: {
    model: 'text-embedding-ada-002',
    input: 'What is AMOS?'
  }
)
query_vector = embedding_result['data'][0]['embedding']

# Query Pinecone
client = Pinecone::Client.new(api_key: ENV['PINECONE_API_KEY'])
index = client.index(store.pinecone_index)

results = index.query(
  namespace: store.pinecone_namespace,
  top_k: 5,
  vector: query_vector,
  include_metadata: true
)

results['matches'].each do |match|
  puts "Score: #{match['score']}"
  puts "Content: #{match['metadata']['content']}"
end
```

### Delete Namespace
```ruby
store = RagStore.find(1)

client = Pinecone::Client.new(api_key: ENV['PINECONE_API_KEY'])
index = client.index(store.pinecone_index)

# Delete all vectors in namespace
index.delete(namespace: store.pinecone_namespace, delete_all: true)

puts "✅ Namespace deleted"
```

## Document Processing

### Process Single Document
```ruby
processor = DocumentProcessorService.new

result = processor.process_documents([{
  content: "Your document content here",
  filename: "test.txt",
  mime_type: "text/plain"
}])

puts "Success: #{result[:success]}"
puts "Chunks: #{result[:chunks].size}"
```

### Process Multiple Files
```ruby
processor = DocumentProcessorService.new

documents = [
  { content: File.read('doc1.pdf'), filename: 'doc1.pdf', mime_type: 'application/pdf' },
  { content: File.read('doc2.txt'), filename: 'doc2.txt', mime_type: 'text/plain' }
]

result = processor.process_documents(documents)

result[:chunks].each do |chunk|
  puts "Source: #{chunk[:metadata][:source]}"
  puts "Content: #{chunk[:content][0..100]}..."
end
```

### Custom Chunking
```ruby
processor = DocumentProcessorService.new

# Semantic chunking (default)
chunks = processor.chunk_text("Your text...", strategy: 'semantic')

# Fixed-size chunking
chunks = processor.chunk_text("Your text...", strategy: 'fixed', chunk_size: 500)

# Custom chunking
text = "Your text..."
custom_chunks = text.split(/\n\n+/).map.with_index do |para, idx|
  {
    content: para.strip,
    metadata: { chunk_index: idx, type: 'paragraph' }
  }
end
```

### Check Docling Availability
```ruby
if DoclingBridgeService.available?
  puts "✅ Docling available (advanced PDF processing)"
else
  puts "⚠️  Docling unavailable (using fallback)"
end
```

## Debugging

### Check Environment
```bash
docker compose exec web rails runner "
  puts 'OpenAI Key: ' + (ENV['OPENAI_API_KEY'] ? '✅ Set' : '❌ Missing')
  puts 'Pinecone Key: ' + (ENV['PINECONE_API_KEY'] ? '✅ Set' : '❌ Missing')
  puts 'Redis URL: ' + (ENV['REDIS_URL'] || 'Not set')
"
```

### Test OpenAI Connection
```ruby
client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])

result = client.embeddings(
  parameters: {
    model: 'text-embedding-ada-002',
    input: 'test'
  }
)

puts "✅ OpenAI working, dimensions: #{result['data'][0]['embedding'].size}"
```

### Test Pinecone Connection
```ruby
client = Pinecone::Client.new(api_key: ENV['PINECONE_API_KEY'])
indexes = client.list_indexes

puts "✅ Pinecone working, indexes: #{indexes.map { |i| i['name'] }.join(', ')}"
```

### Inspect Embedding Cache
```ruby
# Get all cached embeddings
cache_keys = Redis.current.keys('rag:embedding:*')
puts "Cached embeddings: #{cache_keys.size}"

# Sample cache entry
if cache_keys.any?
  key = cache_keys.first
  value = Redis.current.get(key)
  embedding = JSON.parse(value)

  puts "Sample embedding:"
  puts "  Key: #{key}"
  puts "  Dimensions: #{embedding.size}"
  puts "  Sample values: #{embedding.first(5).inspect}"
end
```

### Trace Query Performance
```ruby
require 'benchmark'

entity = Entity.first
store = RagStore.accessible_by(entity).first
service = RagStoreService.new

time = Benchmark.measure do
  result = service.query_rag_store(
    store.id,
    "What is AMOS?",
    current_entity: entity,
    top_k: 5
  )

  puts "Results: #{result[:chunks].size}"
end

puts "Query time: #{(time.real * 1000).round(0)}ms"
```

### Debug Failed Queries
```ruby
entity = Entity.first
store = RagStore.find(1)

service = RagStoreService.new

begin
  result = service.query_rag_store(
    store.id,
    "test query",
    current_entity: entity
  )

  if result[:success]
    puts "✅ Query successful"
  else
    puts "❌ Query failed: #{result[:error]}"
  end
rescue => e
  puts "❌ Exception: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).join("\n")
end
```

### Validate RAG Store
```ruby
store = RagStore.find(1)

puts "Store Validation:"
puts "  ID: #{store.id}"
puts "  Name: #{store.name}"
puts "  Type: #{store.store_type}"
puts "  Entity ID: #{store.entity_id || 'None (system store)'}"
puts "  Status: #{store.status}"
puts "  Pinecone Index: #{store.pinecone_index}"
puts "  Namespace: #{store.pinecone_namespace}"
puts "  Created: #{store.created_at}"

# Validate database
if store.valid?
  puts "  ✅ Valid"
else
  puts "  ❌ Invalid: #{store.errors.full_messages.join(', ')}"
end

# Check Pinecone namespace exists
client = Pinecone::Client.new(api_key: ENV['PINECONE_API_KEY'])
index = client.index(store.pinecone_index)
stats = index.describe_index_stats(namespace: store.pinecone_namespace)

if stats['namespaces'][store.pinecone_namespace]
  vector_count = stats['namespaces'][store.pinecone_namespace]['vector_count']
  puts "  ✅ Pinecone namespace exists (#{vector_count} vectors)"
else
  puts "  ❌ Pinecone namespace not found"
end
```

## Common Patterns

### Pattern: Safe RAG Query with Fallback
```ruby
def safe_rag_query(entity, query, fallback_message = "No information found")
  stores = RagStore.accessible_by(entity)
                   .where(store_type: 'entity', status: 'active')

  return fallback_message if stores.empty?

  service = RagStoreService.new
  results = stores.flat_map do |store|
    result = service.query_rag_store(store.id, query, current_entity: entity)
    result[:chunks]
  end.sort_by { |c| -c[:score] }.first(5)

  results.any? ? results : fallback_message
rescue => e
  Rails.logger.error("RAG query failed: #{e.message}")
  fallback_message
end
```

### Pattern: Batch Document Upload
```ruby
def batch_upload_documents(entity, user, files)
  processor = DocumentProcessorService.new
  rag_service = RagStoreService.new

  files.each do |file|
    # Process document
    result = processor.process_documents([{
      content: file.read,
      filename: file.original_filename,
      mime_type: file.content_type
    }])

    next unless result[:success]

    # Create RAG store
    rag_service.create_rag_store(
      File.basename(file.original_filename, '.*'),
      result[:chunks],
      { entity: entity, user: user, store_type: 'entity' }
    )
  end
end
```

### Pattern: Query with Relevance Threshold
```ruby
def query_with_threshold(entity, query, min_score: 0.75)
  stores = RagStore.accessible_by(entity).where(status: 'active')
  service = RagStoreService.new

  results = stores.flat_map do |store|
    result = service.query_rag_store(store.id, query, current_entity: entity)
    result[:chunks]
  end

  # Filter by minimum score
  results.select { |c| c[:score] >= min_score }
         .sort_by { |c| -c[:score] }
end
```

## Useful Console Commands

```ruby
# Quick stats
puts "Total RAG Stores: #{RagStore.count}"
puts "System Stores: #{RagStore.where(store_type: 'system').count}"
puts "Entity Stores: #{RagStore.where(store_type: 'entity').count}"
puts "Active Stores: #{RagStore.where(status: 'active').count}"

# Entity breakdown
Entity.find_each do |entity|
  count = RagStore.where(entity: entity).count
  puts "#{entity.name}: #{count} stores" if count > 0
end

# Recent uploads
RagStore.order(created_at: :desc).limit(5).each do |store|
  puts "#{store.name} - #{store.store_type} - #{store.created_at.strftime('%Y-%m-%d')}"
end

# Storage usage
total_chunks = RagStore.sum(:chunk_count) || 0
puts "Total chunks across all stores: #{total_chunks}"
```

## Rake Task Reference

```bash
# Load system docs
rails rag:load_amos_docs
rails rag:load_integration_docs

# List stores
rails rag:list

# Test query
rails rag:test_query[1,"AMOS","What is Scout?"]

# Health check
rails rag:health

# Cache stats
rails rag:cache_stats
```

## Related Files
- [SKILL.md](../SKILL.md) - Full RAG development guide
- [app/models/rag_store.rb](../../../../app/models/rag_store.rb)
- [app/services/rag_store_service.rb](../../../../app/services/rag_store_service.rb)
- [lib/tasks/rag.rake](../../../../lib/tasks/rag.rake)
