# RAG Testing Guide

Complete guide for testing the AMOS RAG (Retrieval-Augmented Generation) system.

---

## 📋 Test Suite Overview

The RAG system has three levels of testing:

1. **Unit Tests** - Fast, no external API calls (run automatically)
2. **Integration Tests** - Require valid API keys (manual)
3. **End-to-End Tests** - Full workflow validation (manual)

---

## 🚀 Running Tests

### Quick Unit Tests (No API Keys Required)

```bash
# Run all RAG unit tests
podman compose exec web rails test test/services/rag_store_service_comprehensive_test.rb

# Expected output:
# 14 runs, 29 assertions, 0 failures, 0 errors, 7 skips
# Time: ~0.3s
```

**What's Tested:**
- ✅ Service initialization
- ✅ Namespace generation (entity vs system)
- ✅ Access control enforcement
- ✅ Security validations

**Skipped Tests** (require API keys):
- Create RAG store
- Query RAG store
- Embedding cache
- Host-based indexing

### End-to-End Tests (Require API Keys)

#### Prerequisites

1. **Valid API Keys:**
   ```bash
   # .env file
   OPENAI_API_KEY=sk-proj-your-key-here
   PINECONE_API_KEY=pcsk-your-key-here
   PINECONE_REGION=us-east-1
   ```

2. **Pinecone Indexes Created:**
   - `amos-system-knowledge` (1536 dimensions, cosine)
   - `amos-entity-knowledge` (1536 dimensions, cosine)

3. **OpenAI Credits:** Account must have available credits

#### Run E2E Tests

```bash
# Restart services to load new env vars
podman compose down && podman compose up -d

# Wait for services to start
sleep 45

# Run end-to-end test
podman compose exec web rails test test/integration/rag_end_to_end_test.rb
```

**What's Tested:**
- ✅ Complete RAG workflow (create, store, query)
- ✅ Multi-tenant isolation
- ✅ System vs entity stores
- ✅ Access control enforcement
- ✅ Metadata tracking
- ✅ Performance benchmarks (optional)
- ✅ Cache effectiveness (optional)

---

## 📊 Test Coverage

### Unit Tests (7 passing)

| Test | Description | Status |
|------|-------------|--------|
| `initialize` | Verifies Pinecone, OpenAI, Cache setup | ✅ |
| `generate_namespace` (entity) | Entity-scoped namespace format | ✅ |
| `generate_namespace` (system) | System namespace format | ✅ |
| `can_access_rag_store` (system) | System stores accessible to all | ✅ |
| `can_access_rag_store` (entity) | Entity stores restricted | ✅ |
| `raises_SecurityError` | Entity store without entity fails | ✅ |
| `query_rag_store` access control | Cross-entity access denied | ✅ |

### Integration Tests (skipped by default)

| Test | Description | Requires |
|------|-------------|----------|
| Create entity store | Full RAG store creation | API keys |
| Create system store | Shared knowledge base | API keys |
| Query with metadata | Semantic search | API keys |
| Embedding cache | Cache hit performance | API keys + Redis |
| Host-based indexing | Modern Pinecone API | API keys |
| Enhanced metadata | Phase 3 features | API keys |

### E2E Test Workflow

1. **Setup**: Creates test documents with metadata
2. **Store**: Creates entity-scoped RAG store
3. **Query**: Tests semantic search
4. **Access Control**: Verifies entity isolation
5. **System Store**: Tests shared knowledge
6. **Metadata**: Validates enhanced tracking
7. **Cleanup**: Removes test data

---

## 🧪 Manual Testing Steps

### Test 1: Create Your First RAG Store

```bash
podman compose exec web rails console
```

```ruby
# Get your entity and user
entity = Entity.first
user = entity.users.first

# Create a RAG service
service = RagStoreService.new

# Create test documents
chunks = [
  {
    content: "AMOS is a conversational AI platform using AWS Bedrock.",
    metadata: { source: "docs/intro.md", page: 1, heading: "Introduction" }
  },
  {
    content: "RAG enables semantic search over your documents.",
    metadata: { source: "docs/rag.md", page: 1, heading: "What is RAG?" }
  }
]

# Create the RAG store (entity-scoped)
result = service.create_rag_store(
  "test-docs",
  chunks,
  { entity: entity, user: user, name: "Test Documentation" }
)

# Check result
puts result[:success]  # => true
puts result[:rag_store].name  # => "Test Documentation"
puts result[:rag_store].chunk_count  # => 2
```

### Test 2: Query the RAG Store

```ruby
# Query your RAG store
rag_store = RagStore.last

results = service.query_rag_store(
  rag_store.id,
  "What is AMOS?",
  current_entity: entity,
  top_k: 3
)

# View results
results.each_with_index do |result, i|
  puts "\n#{i + 1}. Score: #{result[:score].round(3)}"
  puts "   Content: #{result[:content]}"
  puts "   Source: #{result[:source]}"
end
```

### Test 3: Verify Multi-Tenant Isolation

```ruby
# Try to access another entity's RAG store
other_entity = Entity.second

begin
  service.query_rag_store(rag_store.id, "test", current_entity: other_entity)
  puts "❌ FAILED: Should have raised SecurityError"
rescue SecurityError => e
  puts "✅ PASSED: #{e.message}"
end
```

### Test 4: Create System Store (Shared)

```ruby
system_chunks = [
  {
    content: "Stripe API documentation: Create customers and subscriptions.",
    metadata: { source: "stripe.com/docs", type: "api_docs" }
  }
]

system_result = service.create_rag_store(
  "stripe-api",
  system_chunks,
  { name: "Stripe API Docs", store_type: "system" }
)

# Verify any entity can access
store = system_result[:rag_store]
puts store.store_type  # => "system"
puts store.entity_id   # => nil

# Both entities can query
results1 = service.query_rag_store(store.id, "stripe", current_entity: Entity.first)
results2 = service.query_rag_store(store.id, "stripe", current_entity: Entity.second)

puts "✅ Both entities can access system store"
```

---

## 🐛 Troubleshooting Tests

### OpenAI 401 Unauthorized

```
Error: Invalid API key
```

**Fix:**
1. Check `.env` has `OPENAI_API_KEY=sk-proj-...`
2. Verify no quotes around the key
3. Restart services: `podman compose down && podman compose up -d`

### OpenAI 429 Insufficient Quota

```
Error: You exceeded your current quota
```

**Fix:**
1. Go to https://platform.openai.com/account/billing
2. Add credits ($5-10 is plenty for testing)
3. Wait 5-10 minutes for quota to update

### Pinecone 401 Unauthorized

```
Error: Invalid API Key
```

**Fix:**
1. Get new API key from https://app.pinecone.io
2. Modern keys start with `pcsk_` or `pc-`
3. Legacy keys (`a9e7aee5-...`) won't work
4. Update `.env` and restart services

### Pinecone Index Not Found

```
Error: Index 'amos-system-knowledge' not found
```

**Fix:**
1. Go to https://app.pinecone.io/indexes
2. Create index:
   - Name: `amos-system-knowledge`
   - Dimensions: `1536`
   - Metric: `cosine`
   - Type: Serverless
   - Cloud: AWS
   - Region: `us-east-1`
3. Repeat for `amos-entity-knowledge`

### Redis Connection Refused

```
Error: Redis connection refused
```

**Fix:**
```bash
# Check Redis is running
podman compose ps redis

# Restart if needed
podman compose restart redis
```

---

## 📈 Performance Expectations

### Query Performance

**With Embedding Cache:**
- First query: ~1-3 seconds (API call + Pinecone)
- Repeat query: ~0.5-1 second (cache hit)

**Without Cache:**
- All queries: ~1-3 seconds

### Embedding Generation

**Batch Processing:**
- 100 chunks: ~5-10 seconds
- 1000 chunks: ~30-60 seconds
- Uses batch API for efficiency

**Cache Hit Rates:**
- Initial load: 0%
- After repeated queries: 70-90%

---

## 🔐 Security Tests

All tests verify:

1. **Entity Isolation**:
   - Entity stores only accessible by owner
   - Cross-entity queries raise `SecurityError`

2. **System Store Access**:
   - Any entity can query system stores
   - No entity prefix in namespace

3. **Namespace Format**:
   - Entity: `entity_{id}_{app}_timestamp`
   - System: `system_{app}_timestamp`

---

## 📝 Test Data Cleanup

After manual testing:

```ruby
# Delete test RAG stores
RagStore.where(name: "Test Documentation").destroy_all
RagStore.where(name: "Stripe API Docs").destroy_all

# Or delete all stores (careful!)
# RagStore.destroy_all
```

---

## ✅ CI/CD Integration

### GitHub Actions Example

```yaml
name: RAG Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Run Unit Tests
        run: |
          podman compose up -d db redis
          podman compose run web rails test test/services/rag_store_service_comprehensive_test.rb

      # E2E tests only on main branch with secrets
      - name: Run E2E Tests
        if: github.ref == 'refs/heads/main'
        env:
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
          PINECONE_API_KEY: ${{ secrets.PINECONE_API_KEY }}
        run: |
          podman compose run web rails test test/integration/rag_end_to_end_test.rb
```

---

## 📚 Related Documentation

- [RAG Architecture](./RAG_ARCHITECTURE.md)
- [Multi-Tenant RAG](./MULTI_TENANT_RAG_ARCHITECTURE.md)
- [Docling Setup](./DOCLING_SETUP.md)
- [RAG Docker Setup](./RAG_DOCKER_SETUP.md)

---

## 🎯 Success Checklist

- [ ] Unit tests pass locally
- [ ] Have valid OpenAI API key with credits
- [ ] Have modern Pinecone API key
- [ ] Created required Pinecone indexes
- [ ] E2E test completes successfully
- [ ] Can query RAG stores via Rails console
- [ ] Multi-tenant isolation verified
- [ ] Cache is working (Redis connected)

---

**Test Status:** ✅ All unit tests passing (29 assertions)
**Last Updated:** 2025-10-18
**Requires:** OpenAI API, Pinecone v1.2+, Redis (optional)
