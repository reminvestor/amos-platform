# RAG Visual Testing Guide

Step-by-step guide to visually verify RAG is working in Docker.

---

## 🚀 Quick Start - Automated Visual Test

### Option 1: Run Visual Test Script (Recommended)

```bash
# From project root
./scripts/test-rag.sh
```

This will:
- ✅ Check all API keys are configured
- ✅ Create entity-scoped test RAG store
- ✅ Create system (shared) RAG store
- ✅ Run test queries with visual results
- ✅ Verify multi-tenant isolation
- ✅ Display colorized output

**Example Output:**
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
  Using Entity: #1 - Acme Corp
  Using User: #1 - admin@example.com

  Creating RAG store with 3 chunks...

  ✅ RAG Store Created Successfully!

  📦 Store Details:
     ID: 1
     Name: AMOS Visual Test Documentation
     Type: entity
     Entity ID: 1
     Chunk Count: 3
     Pinecone Index: amos-entity-knowledge
     Namespace: entity_1_amos_visual_test_1729268500

  📊 Metadata:
     Page filtering: ✅
     Heading search: ✅
     Chunks with pages: 3
     Chunks with headings: 3

🔍 STEP 5: Query RAG Store
--------------------------------------------------------------------------------

  Query 1: "What is AMOS?"
  Found 2 result(s):

  1. Score: 94.2%
     Content: AMOS is a conversational AI platform that uses AWS Bedrock and Claude...
     Source: docs/introduction.md
     Type: documentation

  2. Score: 78.5%
     Content: The RAG (Retrieval-Augmented Generation) system in AMOS uses...
     Source: docs/rag-architecture.md
     Type: documentation

🔐 STEP 6: Test Multi-Tenant Isolation
--------------------------------------------------------------------------------
  Attempting to access Entity 1's store from Entity 2...
  ✅ Access Denied (as expected)
     Error: Access denied to RAG store 1

🌍 STEP 7: Create System Store (Shared Knowledge)
--------------------------------------------------------------------------------
  Creating system RAG store (accessible to all entities)...

  ✅ System Store Created!
     ID: 2
     Type: system
     Entity ID: nil (nil = shared)
     Namespace: system_stripe_api_test_1729268510

  Testing system store access...
  ✅ Entity 1 can access (1 results)
  ✅ Entity 2 can access (1 results)

================================================================================
                    ✅ RAG SYSTEM TEST COMPLETE!
================================================================================
```

---

## 📊 Option 2: Manual Rails Console Testing

### Step 1: Open Rails Console

```bash
podman compose exec web rails console
```

### Step 2: Check Environment

```ruby
# Verify API keys are loaded
puts "OpenAI: #{ENV['OPENAI_API_KEY']&.slice(0, 15)}..."
puts "Pinecone: #{ENV['PINECONE_API_KEY']&.slice(0, 15)}..."
puts "Redis: #{ENV['REDIS_URL']}"

# Check database
puts "Entities: #{Entity.count}"
puts "Users: #{User.count}"
puts "RAG Stores: #{RagStore.count}"
```

### Step 3: Initialize RAG Service

```ruby
service = RagStoreService.new

# Verify clients initialized
service.instance_variable_get(:@pinecone)    # => Pinecone::Client
service.instance_variable_get(:@openai_client)  # => OpenAI::Client
```

### Step 4: Create Test RAG Store

```ruby
# Get entity and user
entity = Entity.first
user = entity.users.first

# Create test chunks
chunks = [
  {
    content: "AMOS is a conversational AI marketing platform.",
    metadata: {
      source: "docs/intro.md",
      page: 1,
      heading: "Introduction"
    }
  },
  {
    content: "RAG enables semantic search over documents.",
    metadata: {
      source: "docs/rag.md",
      page: 1,
      heading: "RAG Overview"
    }
  }
]

# Create entity-scoped store
result = service.create_rag_store(
  "my-test-docs",
  chunks,
  { entity: entity, user: user, name: "My Test Docs" }
)

# Check result
puts result[:success]  # => true
store = result[:rag_store]
puts "Store ID: #{store.id}"
puts "Namespace: #{store.pinecone_namespace}"
puts "Type: #{store.store_type}"
puts "Chunks: #{store.chunk_count}"
```

**Expected Output:**
```ruby
true
Store ID: 1
Namespace: entity_1_my_test_docs_1729268500
Type: entity
Chunks: 2
```

### Step 5: Query the RAG Store

```ruby
# Run a query
results = service.query_rag_store(
  store.id,
  "What is AMOS?",
  current_entity: entity,
  top_k: 3
)

# Display results
results.each_with_index do |result, i|
  puts "\n#{i + 1}. Score: #{(result[:score] * 100).round(1)}%"
  puts "   #{result[:content]}"
  puts "   Source: #{result[:source]}"
end
```

**Expected Output:**
```
1. Score: 92.3%
   AMOS is a conversational AI marketing platform.
   Source: docs/intro.md

2. Score: 76.8%
   RAG enables semantic search over documents.
   Source: docs/rag.md
```

### Step 6: Test Multi-Tenant Isolation

```ruby
# Get another entity
other_entity = Entity.second

# Try to access first entity's store
begin
  service.query_rag_store(store.id, "test", current_entity: other_entity)
  puts "❌ SECURITY FAILED - Cross-entity access allowed!"
rescue SecurityError => e
  puts "✅ Security working: #{e.message}"
end
```

**Expected Output:**
```
✅ Security working: Access denied to RAG store 1
```

### Step 7: Inspect Namespaces

```ruby
# View all RAG stores and their namespaces
RagStore.all.each do |store|
  puts "\n#{store.name}"
  puts "  Type: #{store.store_type}"
  puts "  Entity: #{store.entity_id || 'shared'}"
  puts "  Namespace: #{store.pinecone_namespace}"
  puts "  Chunks: #{store.chunk_count}"
end
```

**Example Output:**
```
My Test Docs
  Type: entity
  Entity: 1
  Namespace: entity_1_my_test_docs_1729268500
  Chunks: 2

Stripe API Docs
  Type: system
  Entity: shared
  Namespace: system_stripe_api_1729268600
  Chunks: 5
```

---

## 🔍 Option 3: Watch Docker Logs in Real-Time

### Terminal 1: Watch Rails Logs

```bash
podman compose logs -f web | grep -E "(RAG|Pinecone|OpenAI|embedding)"
```

### Terminal 2: Run Operations

```bash
podman compose exec web rails console
```

```ruby
# In console, create a RAG store
service = RagStoreService.new
result = service.create_rag_store("test", [{ content: "test", metadata: { source: "test" } }], { entity: Entity.first, user: User.first })
```

**Watch Terminal 1 for logs:**
```
🗄️ Creating RAG store for test with 1 chunks
📍 Store type: entity, Index: amos-entity-knowledge, Namespace: entity_1_test_1729268500
🧮 Generating embeddings for 1 chunks (cache: on)
📤 Storing 1 vectors in Pinecone
🔗 Index amos-entity-knowledge host: amos-entity-knowledge-abc123.svc.pinecone.io
✅ Stored 1 vectors successfully
```

---

## 📊 Option 4: Database Inspection

### Check RAG Store Records

```bash
podman compose exec web rails dbconsole
```

```sql
-- View all RAG stores
SELECT id, name, store_type, entity_id, chunk_count, pinecone_namespace
FROM rag_stores
ORDER BY created_at DESC;

-- View entity-scoped stores
SELECT * FROM rag_stores WHERE store_type = 'entity';

-- View system stores
SELECT * FROM rag_stores WHERE store_type = 'system';

-- Count stores per entity
SELECT entity_id, COUNT(*) as store_count
FROM rag_stores
WHERE store_type = 'entity'
GROUP BY entity_id;
```

---

## 🎨 Option 5: Web UI Testing (Scout)

### Prerequisites

1. **Start Docker:**
   ```bash
   podman compose up -d
   ```

2. **Visit:** http://localhost:3000

3. **Sign in or create account**

### Upload Document Test

1. Go to Scout chat interface
2. Click "Upload Document" or attach file
3. Upload a PDF file
4. Wait for processing (~5-30 seconds)
5. Ask questions about the document

**Example:**
- Upload: "company_handbook.pdf"
- Ask: "What is our vacation policy?"
- See: RAG retrieves relevant sections from the PDF

### Check Processing

```bash
# In another terminal, watch logs
podman compose logs -f web

# Look for:
# 📄 Processing document: company_handbook.pdf
# 🔧 Using Docling for PDF processing
# 🧮 Generating embeddings for 45 chunks
# 📤 Storing 45 vectors in Pinecone
# ✅ RAG store created: company_handbook (45 chunks)
```

---

## 🧹 Cleanup After Testing

### Remove Test RAG Stores

```bash
podman compose exec web rails console
```

```ruby
# Delete all test stores
RagStore.where("name LIKE '%test%' OR name LIKE '%Test%'").destroy_all

# Or delete specific store
RagStore.find(1).destroy

# Or delete all stores (careful!)
# RagStore.destroy_all
```

### Check Pinecone Directly

```bash
podman compose exec web rails runner "
  client = Pinecone::Client.new

  # List indexes
  response = client.list_indexes
  puts response['indexes'].inspect

  # Describe an index
  info = client.describe_index('amos-entity-knowledge')
  puts 'Host: ' + info['host']
  puts 'Dimension: ' + info['dimension'].to_s
  puts 'Records: ' + info['status']['vector_count'].to_s
"
```

---

## 🐛 Troubleshooting Visual Tests

### Issue: "OpenAI quota exceeded"

**Symptom:**
```
Error: You exceeded your current quota
```

**Fix:**
1. Add credits at https://platform.openai.com/account/billing
2. Wait 5-10 minutes
3. Retry test

### Issue: "Invalid API Key"

**Symptom:**
```
Error: Invalid API Key (401)
```

**Fix:**
```bash
# Check .env file
cat .env | grep -E "(OPENAI|PINECONE)"

# Should show (without quotes):
# OPENAI_API_KEY=sk-proj-...
# PINECONE_API_KEY=pcsk-...

# If keys have quotes, remove them
# Restart Docker:
podman compose down && podman compose up -d
```

### Issue: "Index not found"

**Symptom:**
```
Error: Index 'amos-entity-knowledge' not found
```

**Fix:**
1. Go to https://app.pinecone.io/indexes
2. Create index:
   - Name: `amos-entity-knowledge`
   - Dimensions: `1536`
   - Metric: `cosine`
   - Type: Serverless
   - Cloud: AWS
   - Region: `us-east-1`

### Issue: Colorless output

**Symptom:**
No colors in test output

**Fix:**
```bash
# Install colorize gem (should be in Gemfile)
podman compose exec web bundle add colorize

# Or run without colors:
podman compose exec web rails runner scripts/test_rag_visual.rb 2>&1 | cat
```

---

## ✅ Success Indicators

You'll know RAG is working when you see:

1. ✅ **Service Initializes:**
   - Pinecone client created
   - OpenAI client created
   - No errors on initialization

2. ✅ **Store Creation:**
   - Returns `success: true`
   - Gets assigned ID and namespace
   - Chunks stored in Pinecone

3. ✅ **Query Results:**
   - Returns array of results
   - Scores between 0-1
   - Content matches query

4. ✅ **Security:**
   - Cross-entity queries raise `SecurityError`
   - Namespace isolation enforced

5. ✅ **Logs Show:**
   - Embedding generation
   - Pinecone host resolution
   - Vector upsert confirmation

---

## 📚 Next Steps

After visual testing works:

1. **Run automated tests:**
   ```bash
   podman compose exec web rails test test/services/rag_store_service_comprehensive_test.rb
   ```

2. **Try with real documents:**
   - Upload PDFs through Scout UI
   - Test with your actual content

3. **Monitor performance:**
   - Check query response times
   - Watch cache hit rates
   - Monitor Pinecone usage

4. **Production readiness:**
   - Set up proper API key rotation
   - Configure monitoring/alerts
   - Plan for scaling (indexes can handle millions of vectors)

---

**Happy Testing!** 🎉

If you see all green checkmarks, your RAG system is fully operational!
