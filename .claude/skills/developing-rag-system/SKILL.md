# Developing RAG System

Comprehensive guide for modifying, extending, and supporting the AMOS RAG (Retrieval-Augmented Generation) system.

## Description

This skill provides developers with the knowledge and patterns needed to work with AMOS's multi-tenant RAG system. It covers architecture, security patterns, common development tasks, and code examples for extending the system.

**Use this skill when:**
- Adding new RAG features or capabilities
- Modifying RAG processing logic
- Debugging RAG-related issues
- Extending document processing
- Creating new RAG tools for Scout AI
- Understanding RAG security patterns

The skill covers:
- System vs Entity RAG architecture
- Security and multi-tenant isolation
- Document processing pipeline
- Code patterns and examples
- Common development tasks
- Debugging strategies

## Architecture Overview

### Two Types of RAG Stores

**1. System RAG** (`store_type: 'system'`)
- **Purpose**: Shared knowledge accessible to all entities
- **Examples**: AMOS documentation, integration guides, help articles
- **Storage**: `rag_sources/system/` → Database + Pinecone
- **Security**: Accessible to all entities, no entity_id
- **Loading**: Via rake tasks from filesystem

**2. Entity RAG** (`store_type: 'entity'`)
- **Purpose**: Customer-specific private knowledge
- **Examples**: Brand guidelines, product catalogs, internal policies
- **Storage**: Database + Pinecone only (NOT filesystem)
- **Security**: Strict isolation by entity_id, namespace-based
- **Loading**: Via Scout chat ("Load my brand guidelines")

### Data Flow

```
Document Upload
     ↓
DocumentProcessorService
  - Extract text (Docling or fallback)
  - Chunk content (semantic/fixed)
  - Generate embeddings (OpenAI)
     ↓
RagStoreService
  - Create RagStore record (DB)
  - Upload vectors to Pinecone
  - Set entity_id for isolation
     ↓
Database + Pinecone Storage
  - store_type: 'system' or 'entity'
  - entity_id: nil (system) or ID (entity)
  - namespace: unique per store
```

## Key Files and Locations

### Models
- **[app/models/rag_store.rb](../../../app/models/rag_store.rb)** - Core model with security
  - Lines 6-9: Store type enum (`system` vs `entity`)
  - Lines 21-22: Security validations
  - Lines 48-58: `find_accessible()` - Access control
  - Lines 88-96: `accessible_by?()` - Permission check

### Services
- **[app/services/rag_store_service.rb](../../../app/services/rag_store_service.rb)** - Main RAG operations
  - `create_rag_store()` - Create new RAG store
  - `query_rag_store()` - Query with entity scoping
  - `delete_rag_store()` - Remove RAG store
  - `list_rag_stores()` - List accessible stores

- **[app/services/document_processor_service.rb](../../../app/services/document_processor_service.rb)** - Document processing
  - `process_documents()` - Extract, chunk, embed
  - Supports: PDF, DOCX, PPTX, TXT, MD
  - Uses Docling (Python) or fallback extraction

- **[app/services/docling_bridge_service.rb](../../../app/services/docling_bridge_service.rb)** - Python Docling integration
  - Advanced PDF processing
  - Table extraction
  - Layout analysis

### Rake Tasks
- **[lib/tasks/rag.rake](../../../lib/tasks/rag.rake)** - Management commands
  - Lines 2-62: `rag:load_amos_docs` - Load system docs
  - Lines 64-141: `rag:load_integration_docs` - Load integration docs
  - Lines 295-349: `rag:test_query` - Test queries
  - Lines 376-441: `rag:health` - Health check

### Source Directories
- **[rag_sources/system/](../../../rag_sources/system/)** - System RAG sources
  - `amos/` - AMOS platform docs
  - `integrations/` - Integration guides
- **[rag_sources/entity/](../../../rag_sources/entity/)** - Entity RAG (database-only)
  - Contains README explaining upload process

## Security Patterns

### Multi-Tenant Isolation

**Database-Level Scoping:**
```ruby
# ALWAYS scope queries by entity
RagStore.accessible_by(entity)
  .where(store_type: 'system')  # All entities can access
  .or(where(store_type: 'entity', entity: entity))  # Only their docs
```

**Access Control:**
```ruby
# Use find_accessible() instead of find()
store = RagStore.find_accessible(store_id, current_entity)
# Raises RecordNotFound if entity doesn't own the store
```

**Namespace Isolation:**
```ruby
# Each entity gets unique Pinecone namespace
namespace = "entity-#{entity_id}-#{SecureRandom.hex(8)}"
# Prevents vector leakage between entities
```

### Entity RAG Validation

```ruby
# app/models/rag_store.rb
validates :entity, presence: true, if: :store_type_entity?
validates :entity, absence: true, if: :store_type_system?
```

## Common Development Tasks

### Task 1: Add New Document Format Support

**Example: Add CSV support**

1. **Update DocumentProcessorService:**
```ruby
# app/services/document_processor_service.rb
SUPPORTED_FORMATS = %w[pdf docx pptx txt md csv].freeze  # Add csv

def extract_text_from_file(file_path)
  case File.extname(file_path).downcase
  when '.csv'
    extract_text_from_csv(file_path)
  # ... existing cases
  end
end

private

def extract_text_from_csv(file_path)
  require 'csv'
  rows = CSV.read(file_path)
  rows.map { |row| row.join(' | ') }.join("\n")
end
```

2. **Test the new format:**
```bash
docker compose exec web rails console
```
```ruby
service = DocumentProcessorService.new
result = service.process_documents([{
  content: File.read('test.csv'),
  filename: 'test.csv',
  mime_type: 'text/csv'
}])
puts result[:success]
```

### Task 2: Create New RAG Tool for Scout

**Example: Search entity RAG stores**

1. **Create tool file:**
```ruby
# app/services/tools/search_entity_rag_tool.rb
module Tools
  class SearchEntityRagTool < BaseTool
    def self.definition
      {
        name: 'search_entity_rag',
        description: 'Search the entity\'s uploaded RAG documents',
        parameters: {
          type: 'object',
          properties: {
            query: {
              type: 'string',
              description: 'Search query'
            },
            store_name: {
              type: 'string',
              description: 'Optional: Specific RAG store name to search'
            }
          },
          required: ['query']
        }
      }
    end

    def execute(args)
      query = args['query']
      store_name = args['store_name']

      # Get accessible stores
      stores = RagStore.accessible_by(@entity)
                       .where(store_type: 'entity', status: 'active')

      stores = stores.where(name: store_name) if store_name.present?

      if stores.empty?
        return error_response(
          message: "No RAG stores found for this entity"
        )
      end

      # Query all stores
      rag_service = RagStoreService.new
      results = stores.map do |store|
        rag_service.query_rag_store(
          store.id,
          query,
          current_entity: @entity,
          top_k: 3
        )
      end

      # Combine results
      all_chunks = results.flat_map { |r| r[:chunks] }
                          .sort_by { |c| -c[:score] }
                          .first(5)

      success_response(
        message: "Found #{all_chunks.size} relevant results",
        data: {
          query: query,
          results: all_chunks.map { |c|
            {
              content: c[:content],
              score: c[:score],
              source: c[:metadata][:source]
            }
          }
        }
      )
    end
  end
end
```

2. **Tool auto-discovers via ToolCatalog** - No registration needed!

3. **Test in Scout:**
```
User: "Search my brand guidelines for logo usage rules"
Scout: *Uses search_entity_rag tool → Returns results*
```

### Task 3: Modify Chunking Strategy

**Example: Add paragraph-based chunking**

1. **Update DocumentProcessorService:**
```ruby
# app/services/document_processor_service.rb
def chunk_text(text, strategy: ENV.fetch('RAG_CHUNKING_STRATEGY', 'semantic'))
  case strategy
  when 'paragraph'
    chunk_by_paragraphs(text)
  when 'semantic'
    chunk_semantically(text)
  when 'fixed'
    chunk_by_fixed_size(text)
  end
end

private

def chunk_by_paragraphs(text)
  paragraphs = text.split(/\n\n+/)
  paragraphs.map.with_index do |para, idx|
    {
      content: para.strip,
      metadata: {
        chunk_index: idx,
        chunk_type: 'paragraph',
        char_count: para.length
      }
    }
  end
end
```

2. **Set environment variable:**
```bash
# docker-compose.yml or .env
RAG_CHUNKING_STRATEGY=paragraph
```

3. **Test:**
```bash
docker compose exec web rails runner "
  service = DocumentProcessorService.new
  chunks = service.chunk_text('Para 1\n\nPara 2\n\nPara 3', strategy: 'paragraph')
  puts chunks.size  # => 3
"
```

### Task 4: Add RAG Store Metadata

**Example: Track document versioning**

1. **Add migration:**
```bash
docker compose exec web rails generate migration AddVersionToRagStores version:integer
```

2. **Update model:**
```ruby
# app/models/rag_store.rb
class RagStore < ApplicationRecord
  # ... existing code

  validates :version, numericality: { greater_than: 0 }, allow_nil: true

  def increment_version!
    self.version = (version || 0) + 1
    save!
  end
end
```

3. **Update service:**
```ruby
# app/services/rag_store_service.rb
def create_rag_store(name, chunks, options = {})
  # ... existing code

  rag_store = RagStore.create!(
    # ... existing attributes
    version: options[:version] || 1,
    metadata: metadata.merge(
      uploaded_by: options[:user]&.email,
      upload_date: Time.current.iso8601
    )
  )
end
```

### Task 5: Implement RAG Store Archiving

**Example: Soft-delete old RAG stores**

1. **Add migration:**
```bash
docker compose exec web rails generate migration AddArchivedAtToRagStores archived_at:datetime
```

2. **Update model:**
```ruby
# app/models/rag_store.rb
class RagStore < ApplicationRecord
  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  def archive!
    update!(archived_at: Time.current, status: 'archived')
  end

  def unarchive!
    update!(archived_at: nil, status: 'active')
  end
end
```

3. **Update queries:**
```ruby
# Always filter out archived stores
RagStore.accessible_by(entity).active
```

## Debugging Strategies

### Check RAG Store Access

```bash
docker compose exec web rails console
```

```ruby
# Get entity
entity = Entity.find(1)

# List accessible stores
stores = RagStore.accessible_by(entity)
puts "System stores: #{stores.where(store_type: 'system').count}"
puts "Entity stores: #{stores.where(store_type: 'entity').count}"

# Test specific store access
store = RagStore.find(5)
if store.accessible_by?(entity)
  puts "✅ Entity can access store"
else
  puts "❌ Access denied"
end
```

### Inspect Pinecone Namespace

```bash
docker compose exec web rails console
```

```ruby
# Get store
store = RagStore.find(1)

# Connect to Pinecone
client = Pinecone::Client.new(api_key: ENV['PINECONE_API_KEY'])
index = client.index(store.pinecone_index)

# Get stats
stats = index.describe_index_stats(namespace: store.pinecone_namespace)
puts "Vector count: #{stats['namespaces'][store.pinecone_namespace]['vector_count']}"
```

### Test Query Performance

```bash
docker compose exec web rails console
```

```ruby
# Benchmark query
require 'benchmark'

service = RagStoreService.new
entity = Entity.first
store = RagStore.accessible_by(entity).first

time = Benchmark.measure do
  result = service.query_rag_store(
    store.id,
    "What is AMOS?",
    current_entity: entity,
    top_k: 5
  )
  puts "Found #{result[:chunks].size} results"
end

puts "Query time: #{time.real.round(2)}s"
```

### Check Embedding Cache

```bash
docker compose exec web rails runner "
  # Get cache stats
  cache_keys = Redis.current.keys('rag:embedding:*')
  puts 'Cached embeddings: ' + cache_keys.size.to_s

  # Sample cache entry
  if cache_keys.any?
    sample = Redis.current.get(cache_keys.first)
    puts 'Sample cache entry size: ' + sample.bytesize.to_s + ' bytes'
  end
"
```

### Validate Document Processing

```bash
docker compose exec web rails runner "
  service = DocumentProcessorService.new

  # Test document
  doc = {
    content: 'Test content for RAG processing',
    filename: 'test.txt',
    mime_type: 'text/plain'
  }

  result = service.process_documents([doc])

  puts 'Success: ' + result[:success].to_s
  puts 'Chunks: ' + result[:chunks].size.to_s
  puts 'Errors: ' + result[:errors].inspect
"
```

## Testing Your Changes

### Unit Test Pattern

```ruby
# test/services/rag_store_service_test.rb
require 'test_helper'

class RagStoreServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:admin)
    @service = RagStoreService.new
  end

  test "creates entity-scoped RAG store" do
    chunks = [{ content: "Test", metadata: { source: "test.txt" } }]

    result = @service.create_rag_store(
      "Test Store",
      chunks,
      { entity: @entity, user: @user, store_type: 'entity' }
    )

    assert result[:success]
    assert_equal 'entity', result[:rag_store].store_type
    assert_equal @entity.id, result[:rag_store].entity_id
  end

  test "enforces entity isolation" do
    other_entity = entities(:two)
    store = rag_stores(:entity_one)  # Belongs to @entity

    assert_raises(ActiveRecord::RecordNotFound) do
      RagStore.find_accessible(store.id, other_entity)
    end
  end
end
```

### Integration Test Pattern

```ruby
# test/integration/rag_workflow_test.rb
require 'test_helper'

class RagWorkflowTest < ActionDispatch::IntegrationTest
  test "full RAG upload and query workflow" do
    entity = entities(:one)
    user = users(:admin)

    # Upload document
    post rag_stores_path, params: {
      rag_store: {
        name: "Brand Guidelines",
        file: fixture_file_upload('brand_guide.pdf', 'application/pdf')
      }
    }, headers: { 'X-Entity-ID': entity.id }

    assert_response :success
    store = RagStore.last

    # Query RAG
    get query_rag_store_path(store), params: {
      query: "What are our brand colors?"
    }

    assert_response :success
    json = JSON.parse(response.body)
    assert json['chunks'].any?
  end
end
```

## Environment Variables

```bash
# RAG Configuration
RAG_CHUNKING_STRATEGY=semantic       # semantic, fixed, paragraph
RAG_CHUNK_SIZE=1000                  # Characters per chunk
RAG_CHUNK_OVERLAP=200                # Overlap between chunks
RAG_EMBEDDING_CACHE_ENABLED=true    # Enable Redis caching
RAG_EMBEDDING_BATCH_SIZE=100        # Batch size for embeddings

# Required APIs
OPENAI_API_KEY=sk-...               # OpenAI for embeddings
OPENAI_EMBEDDING_MODEL=text-embedding-ada-002
PINECONE_API_KEY=pcsk-...           # Pinecone for vectors
PINECONE_REGION=us-east-1

# Optional
REDIS_URL=redis://localhost:6379/0  # For caching
```

## Rake Commands

```bash
# Load system docs
docker compose exec web rails rag:load_amos_docs
docker compose exec web rails rag:load_integration_docs

# List all RAG stores
docker compose exec web rails rag:list

# Test query (entity_id, app_name, query)
docker compose exec web rails rag:test_query[1,"AMOS","What is Scout?"]

# Health check
docker compose exec web rails rag:health

# Cache statistics
docker compose exec web rails rag:cache_stats

# Delete RAG store
docker compose exec web rails console
RagStore.find(1).destroy  # Also deletes from Pinecone
```

## Common Patterns

### Pattern 1: Entity-Scoped RAG Query

```ruby
def query_user_documents(user, query)
  entity = user.entity

  # Get all entity RAG stores
  stores = RagStore.accessible_by(entity)
                   .where(store_type: 'entity', status: 'active')

  # Query each store
  service = RagStoreService.new
  results = stores.map do |store|
    service.query_rag_store(store.id, query, current_entity: entity)
  end

  # Combine and sort by relevance
  all_chunks = results.flat_map { |r| r[:chunks] }
                      .sort_by { |c| -c[:score] }
                      .first(10)

  all_chunks
end
```

### Pattern 2: Safe RAG Store Creation

```ruby
def create_safe_rag_store(name, file, entity, user)
  # Validate file
  unless file.content_type.in?(['application/pdf', 'text/plain'])
    return { success: false, error: 'Unsupported file type' }
  end

  # Process document
  processor = DocumentProcessorService.new
  result = processor.process_documents([{
    content: file.read,
    filename: file.original_filename,
    mime_type: file.content_type
  }])

  return result unless result[:success]

  # Create RAG store
  rag_service = RagStoreService.new
  rag_service.create_rag_store(
    name,
    result[:chunks],
    {
      entity: entity,
      user: user,
      store_type: 'entity',
      metadata: {
        source_file: file.original_filename,
        uploaded_at: Time.current
      }
    }
  )
rescue => e
  { success: false, error: e.message }
end
```

### Pattern 3: RAG-Augmented Scout Response

```ruby
# app/services/scout_service.rb
def generate_response_with_rag(user, message)
  entity = user.entity

  # Query entity RAG stores
  rag_results = query_user_documents(entity, message)

  # Build context from RAG
  rag_context = if rag_results.any?
    "Relevant information from entity documents:\n\n" +
    rag_results.map { |r| "- #{r[:content]}" }.join("\n")
  else
    ""
  end

  # Send to AI with RAG context
  bedrock_service = BedrockService.new
  bedrock_service.send_message(
    system_prompt: build_system_prompt + "\n\n" + rag_context,
    messages: [{ role: 'user', content: message }],
    tools: Tools::ToolCatalog.instance.get_bedrock_tools
  )
end
```

## Related Skills

- [testing-rag-system](../testing-rag-system/SKILL.md) - Test RAG functionality
- [testing-tools-manually](../testing-tools-manually/SKILL.md) - Test Scout tools
- [managing-docker-development](../managing-docker-development/SKILL.md) - Docker ops

## Related Documentation

- [rag_sources/README.md](../../../rag_sources/README.md) - RAG sources overview
- [rag_sources/QUICK_START.md](../../../rag_sources/QUICK_START.md) - Quick start guide
- [rag_sources/entity/README.md](../../../rag_sources/entity/README.md) - Entity RAG architecture
- [app/models/rag_store.rb](../../../app/models/rag_store.rb) - RagStore model
- [lib/tasks/rag.rake](../../../lib/tasks/rag.rake) - Rake tasks

## Security Checklist

When modifying RAG system:

- [ ] Always use `RagStore.accessible_by(entity)` for queries
- [ ] Use `find_accessible()` instead of `find()` for access control
- [ ] Validate `store_type_entity?` requires `entity_id`
- [ ] Ensure Pinecone namespaces are entity-specific
- [ ] Never leak entity data across boundaries
- [ ] Log all RAG operations for audit trail
- [ ] Test multi-tenant isolation thoroughly
- [ ] Validate file uploads (type, size, content)
- [ ] Sanitize user input before embedding
- [ ] Use encrypted connections to Pinecone

## Performance Considerations

- **Enable embedding cache** - 10x faster for repeated queries
- **Batch embeddings** - Process 100 chunks at a time
- **Index Pinecone queries** - Use metadata filtering
- **Monitor vector count** - Track Pinecone usage
- **Use semantic chunking** - Better relevance than fixed-size
- **Cache RAG results** - 5-minute TTL for common queries
- **Async processing** - Use jobs for large documents

## Troubleshooting

**Issue**: "OpenAI quota exceeded"
```bash
# Solution: Check usage at https://platform.openai.com/usage
# Add credits or reduce embedding batch size
```

**Issue**: "Pinecone namespace not found"
```bash
# Solution: Verify namespace exists
docker compose exec web rails console
store = RagStore.find(1)
puts store.pinecone_namespace  # Should match Pinecone
```

**Issue**: "Cross-entity data leak"
```bash
# Solution: Always use accessible_by()
# BAD:  RagStore.find(id)
# GOOD: RagStore.find_accessible(id, entity)
```

**Issue**: "Slow queries"
```bash
# Solution: Enable embedding cache
# Set: RAG_EMBEDDING_CACHE_ENABLED=true
# Check: docker compose exec web rails rag:cache_stats
```

## Next Steps

After reading this skill, you should be able to:
- ✅ Understand system vs entity RAG architecture
- ✅ Implement proper security patterns
- ✅ Add new document format support
- ✅ Create RAG tools for Scout AI
- ✅ Debug RAG issues effectively
- ✅ Test changes thoroughly
- ✅ Follow AMOS multi-tenant patterns

For testing your RAG changes, use the [testing-rag-system](../testing-rag-system/SKILL.md) skill.
