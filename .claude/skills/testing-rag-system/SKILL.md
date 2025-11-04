# Testing RAG System

Visual testing and validation of the AMOS RAG (Retrieval-Augmented Generation) system.

## Description

This skill performs comprehensive visual testing of the RAG system including:
- API key validation
- Entity-scoped RAG store creation
- System (shared) RAG store creation
- Semantic search queries
- Multi-tenant isolation verification
- Namespace inspection
- Performance metrics

## When to Use

Use this skill when you need to:
- Verify RAG system is configured correctly
- Test RAG functionality after deployment
- Debug RAG issues
- Validate multi-tenant isolation
- See RAG in action with visual output

## Prerequisites

- Docker services running (`docker-compose up -d`)
- Valid `OPENAI_API_KEY` in `.env`
- Valid `PINECONE_API_KEY` in `.env`
- Pinecone indexes created:
  - `amos-system-knowledge` (1536 dimensions, cosine)
  - `amos-entity-knowledge` (1536 dimensions, cosine)
- At least one Entity exists in database

## Usage

```bash
# Run full RAG test suite
.claude/skills/testing-rag-system/scripts/test-rag.sh

# Or run specific steps
docker-compose exec web rails runner .claude/skills/testing-rag-system/scripts/test_rag_visual.rb
```

## What Gets Tested

**Environment Check:**
- ✅ OpenAI API key configured
- ✅ Pinecone API key configured
- ✅ Redis URL configured
- ✅ Database connectivity

**RAG Store Creation:**
- ✅ Entity-scoped store (isolated to one customer)
- ✅ System store (shared across all customers)
- ✅ Metadata tracking (pages, headings, tables)
- ✅ Namespace generation

**Query Functionality:**
- ✅ Semantic search with embeddings
- ✅ Relevance scoring (0-1)
- ✅ Top-K results
- ✅ Metadata in results

**Document Processing & Status Tracking:**
- ✅ Automatic RAG indexing when documents are read
- ✅ Real-time document processing status API (`/scout/document-status/:asset_id`)
- ✅ 4-stage pipeline tracking (Upload → Extraction → Chunking → Embedding)
- ✅ Progress card display in document viewer
- ✅ RagProcessingJob status monitoring

**Security:**
- ✅ Multi-tenant isolation (cross-entity access denied)
- ✅ System store accessibility (all entities can access)
- ✅ Namespace-based data separation

**Performance:**
- ✅ Embedding cache hit rates
- ✅ Query response times
- ✅ Host-based index resolution

## Expected Output

```
================================================================================
                   🧪 AMOS RAG SYSTEM - VISUAL TEST
================================================================================

📋 STEP 1: Environment Check
--------------------------------------------------------------------------------
  ✅ OpenAI       sk-proj-C0pq...
  ✅ Pinecone     pcsk-abc123...
  ✅ Redis        redis://localhost:6379/0

📊 STEP 2: Database Check
--------------------------------------------------------------------------------
  Entities: 2
  Users: 3
  Existing RAG Stores: 0

🔧 STEP 3: Initialize RAG Service
--------------------------------------------------------------------------------
  ✅ RagStoreService initialized
  ✅ Pinecone client: Pinecone::Client
  ✅ OpenAI client: OpenAI::Client
  ✅ Cache enabled: true

📝 STEP 4: Create Entity-Scoped RAG Store
--------------------------------------------------------------------------------
  ✅ RAG Store Created Successfully!

  📦 Store Details:
     Namespace: entity_1_amos_visual_test_1729268500
     Chunk Count: 3

🔍 STEP 5: Query RAG Store
--------------------------------------------------------------------------------
  Query 1: "What is AMOS?"
  Found 2 result(s):

  1. Score: 94.2%
     Content: AMOS is a conversational AI platform...

🔐 STEP 6: Test Multi-Tenant Isolation
--------------------------------------------------------------------------------
  ✅ Access Denied (as expected)

🌍 STEP 7: Create System Store
--------------------------------------------------------------------------------
  ✅ System Store Created!
  ✅ Entity 1 can access
  ✅ Entity 2 can access

================================================================================
                    ✅ RAG SYSTEM TEST COMPLETE!
================================================================================
```

## Troubleshooting

**OpenAI 429 - Quota Exceeded:**
```
❌ Error: You exceeded your current quota
```
→ Add credits at https://platform.openai.com/account/billing

**Pinecone 401 - Invalid API Key:**
```
❌ Error: Invalid API Key
```
→ Get new key from https://app.pinecone.io (format: `pcsk_...`)

**Index Not Found:**
```
❌ Error: Index 'amos-entity-knowledge' not found
```
→ Create indexes at https://app.pinecone.io/indexes

## Cleanup

After testing, remove test RAG stores:

```bash
docker-compose exec web rails console
```

```ruby
RagStore.where("name LIKE '%Test%'").destroy_all
```

## Related Skills

- `testing-workflows-manually` - Test Scout workflows
- `checking-application-health` - Overall health check
- `managing-docker-development` - Docker operations

## Related Documentation

- [RAG Testing Guide](../../../docs/RAG_TESTING_GUIDE.md)
- [RAG Visual Testing](../../../docs/RAG_VISUAL_TESTING.md)
- [RAG Architecture](../../../docs/RAG_ARCHITECTURE.md)
- [Multi-Tenant RAG](../../../docs/MULTI_TENANT_RAG_ARCHITECTURE.md)

## Examples

### Example 1: Quick Health Check

```bash
# Just verify RAG is working
.claude/skills/testing-rag-system/scripts/test-rag.sh | grep "✅"
```

### Example 2: Manual Console Test

```bash
docker-compose exec web rails console
```

```ruby
# Quick RAG test
service = RagStoreService.new
entity = Entity.first
user = entity.users.first

chunks = [{
  content: "Test content for RAG",
  metadata: { source: "test.txt" }
}]

result = service.create_rag_store(
  "quick-test",
  chunks,
  { entity: entity, user: user }
)

puts result[:success]  # => true
```

### Example 3: Watch Logs While Testing

```bash
# Terminal 1
docker-compose logs -f web | grep RAG

# Terminal 2
.claude/skills/testing-rag-system/scripts/test-rag.sh
```

### Example 4: Test Document Upload & Progress Tracking

```bash
# Terminal 1 - Watch logs during document processing
docker-compose logs -f web | grep -E "📤|📚|✅|❌"

# Terminal 2 - In Rails console, upload and read a document
docker-compose exec web rails console

# Then in the console:
entity = Entity.first
user = entity.users.first
context = {}

# Create an ImageAsset (simulating file upload)
file_content = File.read('path/to/document.pdf')
asset = entity.image_assets.create!(
  user: user,
  title: 'Test Document',
  file: file_content,
  source: 'upload'
)

# Read the document - this will trigger RAG indexing automatically
tool = Tools::ReadDocumentTool.new(entity: entity, user: user, context: {})
result = tool.execute(asset_id: asset.id)

# Check status API
curl http://localhost:3000/scout/document-status/#{asset.id}
# Response will include: stage, message, progress_percent, ready_for_chat

# Repeatedly call until complete
# Stage 1: Uploading document to storage
# Stage 2: Extracting text (Docling)
# Stage 3: Breaking into chunks
# Stage 4: Generating embeddings (ready_for_chat: true)
```

### Example 5: Monitor Progress via API

```bash
# Watch document progress in real-time
watch -n 1 "curl -s http://localhost:3000/scout/document-status/ASSET_ID | jq '.'"

# Example response:
# {
#   "asset_id": 123,
#   "status": "embedding",
#   "stage": 4,
#   "total_stages": 4,
#   "message": "Generating embeddings... 45/100 complete",
#   "ready_for_chat": false,
#   "embedded_chunks": 45,
#   "total_chunks": 100,
#   "progress_percent": 45.0
# }
```

## Notes

- Test creates temporary RAG stores (can be cleaned up)
- Requires valid API keys with available quota/credits
- Uses colorized output (requires `colorize` gem)
- Safe to run multiple times
- Does not affect existing RAG stores

## Success Criteria

All steps should show ✅ green checkmarks:
- [x] API keys configured
- [x] RAG service initializes
- [x] Entity store created
- [x] System store created
- [x] Queries return results
- [x] Multi-tenant isolation works
- [x] No errors in output
- [x] Document upload triggers RAG indexing
- [x] Status API returns correct pipeline stages
- [x] Progress card updates in real-time
- [x] Document becomes ready_for_chat after embedding
