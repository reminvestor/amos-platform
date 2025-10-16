# Scout Memory vs RAG: Feature Comparison

## Overview

AMOS has two distinct but complementary memory systems for Scout AI:

1. **Scout Redis Memory** (PR #61) - Short-term conversation history
2. **Docling RAG** - Long-term document knowledge base

**They are NOT redundant** - each serves a different purpose and they work together to enhance Scout's capabilities.

---

## Quick Comparison Table

| Feature | Scout Redis Memory | Docling RAG |
|---------|-------------------|-------------|
| **Purpose** | Conversation recall | Document knowledge base |
| **Data Type** | Chat messages (text) | Document chunks (embedded vectors) |
| **Storage Backend** | Redis (in-memory) | Pinecone (vector database) |
| **Lifetime** | 2 hours (session-based) | Permanent |
| **Search Method** | Keyword/index-based | Semantic similarity (AI-powered) |
| **Scope** | Single conversation | Entity-wide or system-wide |
| **Max Size** | 1,000 messages per session | Unlimited documents |
| **Cost** | Low (Redis memory) | Higher (embeddings + Pinecone storage) |
| **Access Pattern** | Sequential/keyword | Similarity search |
| **Multi-tenant** | Session-isolated | Entity-isolated |

---

## Scout Redis Memory

### Purpose
Allows Scout to remember what was discussed **in the current conversation**. Think of it as Scout's "working memory" for the active chat session.

### Technical Details
- **Storage:** Redis key-value store
- **Structure:** List of conversation messages (role + content + metadata)
- **TTL:** 2 hours (session expires)
- **Capacity:** Last 1,000 messages stored, last 20 in active window
- **Location:** `lib/scout/memory_tools.rb`

### Tools Available to Scout
```ruby
1. retrieve_history(start_index, end_index, count)
   - Get older messages from the conversation
   - Example: "Show me messages 50-60"

2. get_message_count()
   - Get total number of messages in conversation
   - Example: "How long have we been talking?"

3. search_history(keywords, role, max_results)
   - Search conversation for specific keywords
   - Example: "Find when we discussed pricing"
```

### Use Cases
✅ "What did I say earlier about the budget?"
✅ "Can you remind me of the email address I mentioned?"
✅ "Go back to when we were discussing the campaign"
✅ "How many messages have we exchanged?"

### Example Interaction
```
User: "Earlier I mentioned some email addresses for the team"
Scout: [Uses search_history(keywords: "email") to find those messages]
Scout: "Yes, you mentioned john@company.com and sarah@company.com at the beginning of our conversation."
```

---

## Docling RAG (Document Knowledge Base)

### Purpose
Allows Scout to access and search **uploaded documentation and knowledge bases**. Think of it as Scout's "reference library" that persists across all conversations.

### Technical Details
- **Storage:** Pinecone vector database
- **Structure:** Document chunks with embeddings (1536 dimensions, OpenAI)
- **TTL:** Permanent (until explicitly deleted)
- **Capacity:** Unlimited documents
- **Location:** `app/services/rag_store_service.rb`
- **Indexes:**
  - `amos-system-knowledge` (shared AMOS knowledge)
  - `amos-entity-knowledge` (customer-specific data)

### Features
```ruby
1. Multi-tenant isolation
   - Entity-specific namespaces
   - Security boundaries between customers

2. Dual chunking strategies
   - Simple chunking: Fixed size with overlap
   - Semantic chunking: AI-powered context preservation

3. Embedding cache (70% cost savings)
   - Caches embeddings for repeated content
   - 5x faster processing on repeated queries

4. Metadata filtering
   - Filter by source, type, category, tags
   - Date range filtering
```

### Tools Available to Scout
```ruby
1. create_rag_store(app_name, chunks, metadata)
   - Upload and index new documentation
   - Example: "Index our product documentation"

2. query_rag_store(rag_store_id, query, top_k)
   - Search knowledge base semantically
   - Example: "What does our docs say about pricing?"
```

### Use Cases
✅ "What does our product documentation say about API limits?"
✅ "Search our knowledge base for information about GDPR compliance"
✅ "Look up the technical specs from the uploaded PDF"
✅ "Find relevant sections in our user manual about password reset"

### Example Interaction
```
User: "What does our documentation say about webhook configuration?"
Scout: [Uses query_rag_store to search uploaded docs]
Scout: "According to your API documentation (uploaded 2 days ago), webhook configuration requires setting up..."
```

---

## When to Use Each System

### Use Scout Redis Memory When:
- User references something **they said** in **this conversation**
- Need to recall **context from earlier** in the chat
- Tracking conversation flow and continuity
- User says "earlier," "before," "you mentioned," etc.

### Use Docling RAG When:
- User asks about **documentation** or **knowledge base**
- Need to search **uploaded files** or **product docs**
- Answering questions about **company policies** or **technical specs**
- User says "according to docs," "what do our materials say," etc.

---

## How They Work Together

### Scenario 1: Hybrid Query
```
User: "Earlier I asked about pricing. Can you check the docs for the exact tiers?"

Scout process:
1. Uses search_history(keywords: "pricing") → Finds earlier conversation
2. Sees user context: discussing Enterprise tier
3. Uses query_rag_store(query: "Enterprise tier pricing") → Gets official prices
4. Responds with both conversational context AND documentation data
```

### Scenario 2: Document Discussion
```
User: "I just uploaded our product spec. Can you explain the API rate limits?"

Scout process:
1. Uses query_rag_store → Searches uploaded spec for "API rate limits"
2. Finds: "1000 requests per hour for Basic, 10000 for Pro"
3. Stores response in conversation history (Redis)
4. Later if user asks "what were those limits again?" → Uses retrieve_history
```

---

## Architecture Diagrams

### Scout Redis Memory Flow
```
User Message
     ↓
Scout Controller
     ↓
Save to PostgreSQL (scout_messages table)
     ↓
Also save to Redis (session_id key)
     ↓
Active Window: Last 20 messages kept in context
     ↓
Extended History: Up to 1000 messages in Redis
     ↓
Expires after 2 hours
```

### Docling RAG Flow
```
User Uploads Document
     ↓
RagLoaderService
     ↓
Docling Processing (PDF/DOCX → Markdown)
     ↓
Chunking Strategy (Simple or Semantic)
     ↓
Generate Embeddings (OpenAI, with cache)
     ↓
Store in Pinecone (entity namespace)
     ↓
Create RagStore record (PostgreSQL metadata)
     ↓
Available for semantic search (permanent)
```

---

## Performance Characteristics

### Scout Redis Memory
- **Read latency:** < 5ms (Redis in-memory)
- **Write latency:** < 10ms (dual write to PostgreSQL + Redis)
- **Cost:** Minimal (Redis memory)
- **Scalability:** Linear with number of active sessions
- **Best for:** High-frequency, low-latency conversation recall

### Docling RAG
- **Read latency:** 100-300ms (embedding + Pinecone query)
- **Write latency:** 2-5s per document (processing + embedding)
- **Cost:** $0.001 per embedding + Pinecone storage
- **Scalability:** Horizontal (unlimited documents)
- **Best for:** Rich semantic search across large document sets

---

## Database Tables

### Scout Redis Memory
```sql
-- PostgreSQL (permanent record)
scout_messages (id, session_id, role, content, metadata, created_at)

-- Redis (fast access, TTL)
Key: "scout_messages:#{session_id}"
Type: List
TTL: 7200 seconds
```

### Docling RAG
```sql
-- PostgreSQL (metadata only)
rag_stores (
  id, name, app_name, store_type, entity_id,
  pinecone_index, pinecone_namespace,
  chunk_count, metadata, status
)

-- Pinecone (vectors)
Index: amos-entity-knowledge
Namespace: entity_#{entity_id}_#{app_name}
Vectors: 1536-dimensional embeddings
```

---

## Configuration

### Scout Redis Memory
```ruby
# lib/scout/memory_tools.rb
ACTIVE_WINDOW_SIZE = 20    # Messages in active context
MAX_HISTORY_SIZE = 1000    # Total messages stored
SESSION_TTL = 7200         # 2 hours in seconds

# Requirements
- Redis instance ($redis global)
- PostgreSQL (scout_messages table)
```

### Docling RAG
```ruby
# app/services/rag_config.rb
EMBEDDING_DIMENSION = 1536         # OpenAI embeddings
SYSTEM_INDEX = "amos-system-knowledge"
ENTITY_INDEX = "amos-entity-knowledge"

# Requirements
- Pinecone API key (ENV["PINECONE_API_KEY"])
- OpenAI API key (ENV["OPENAI_API_KEY"])
- PostgreSQL (rag_stores table)
```

---

## Testing

### Scout Redis Memory
See: `docs/SCOUT_MEMORY_TESTING_GUIDE.md`

```bash
# Test memory tools
rails console
memory = Scout::MemoryTools.new("test-session-123")
memory.store_message("user", "Hello")
memory.get_message_count
```

### Docling RAG
See: `docs/DOCLING_SETUP.md`

```bash
# Test RAG store
rails console
service = RagStoreService.new
service.create_rag_store("test-app", [
  { content: "Test chunk", metadata: {} }
], { entity: Entity.first })
```

---

## Migration & Deployment

### Redis Memory (PR #61)
- ✅ No database migrations needed (uses existing scout_messages)
- ✅ Requires Redis instance
- ✅ Backward compatible (graceful degradation if Redis unavailable)
- ✅ Can deploy independently

### Docling RAG
- ⚠️ Requires Pinecone account setup
- ⚠️ Requires migration: `rails db:migrate` (creates rag_stores table)
- ⚠️ Requires Docling Python service (optional, for PDF processing)
- ⚠️ Requires OpenAI API credits for embeddings

---

## Cost Analysis

### Scout Redis Memory
**Per 10,000 conversations:**
- Redis memory: ~100MB × $0.10/GB/month = **$0.01/month**
- PostgreSQL storage: Negligible (text storage)
- **Total: < $1/month** for most workloads

### Docling RAG
**Per 1,000 documents (avg 10 chunks each):**
- OpenAI embeddings: 10,000 chunks × $0.0001 = **$1.00**
- Pinecone storage: 10,000 vectors × $0.000001/month = **$0.01/month**
- Pinecone queries: 100,000 queries × $0.00001 = **$1.00/month**
- **Total: ~$2-3/month** for active usage

With embedding cache: **70% reduction** → ~$0.60/month

---

## Conclusion

**Both features are essential and complementary:**

- **Scout Redis Memory** = Short-term conversation context (what we talked about)
- **Docling RAG** = Long-term knowledge base (what our docs say)

**Recommendation:** Deploy both features to give Scout:
1. Conversational continuity within sessions
2. Access to institutional knowledge across sessions

They do NOT conflict and serve completely different use cases.

---

## Scalability Analysis & Concerns

### Pinecone Index Structure

```
amos-system-knowledge (Index)
├── system_stripe_1234567890      ← All entities can access
├── system_hubspot_9876543210
└── system_mailgun_5555555555

amos-entity-knowledge (Index)
├── entity_1_custom_1234567890    ← Entity 1 only
├── entity_1_internal_1111111111
├── entity_2_private_2222222222   ← Entity 2 only
└── entity_2_docs_3333333333
```

### ✅ System Knowledge - HIGHLY SCALABLE
- **Single index** with multiple namespaces
- **Shared across all entities** (Stripe docs, HubSpot docs, etc.)
- **Cost:** Fixed (one-time embedding cost per system integration)
- **Queries:** O(1) - same regardless of customer count
- **Storage:** ~1GB for all system docs
- **Verdict:** Perfect - scales to millions of customers without additional cost

### ⚠️ Entity Knowledge - SCALABILITY CONCERN
- **Single index** with entity-specific namespaces
- **Grows linearly** with number of customers
- **Problem at scale:**

```
Current: 10 customers
├── entity_1_*  (5 namespaces × 1000 vectors each)
├── entity_2_*  (5 namespaces × 1000 vectors each)
...
Total: 50,000 vectors in one index

At 10,000 customers:
├── entity_1_* through entity_10000_*
Total: 50,000,000 vectors in ONE index
```

### Pinecone Limits & Costs

| Tier | Max Vectors/Index | Cost |
|------|-------------------|------|
| **Starter** | 100K vectors | Free |
| **Standard** | 5M vectors | $70/month |
| **Enterprise** | 50M+ vectors | $1000+/month |

**Concern:** Single `amos-entity-knowledge` index hits limits at:
- **100 customers** (5M vectors) → Need Standard tier ($70/mo)
- **1,000 customers** (50M vectors) → Need Enterprise tier ($1000+/mo)
- **10,000 customers** → Not feasible in single index

### Recommended Solution: Index Sharding

**Option 1: Namespace-per-entity (current) - NOT SCALABLE**
```ruby
# Current implementation
namespace = "entity_#{entity.id}_#{app_name}"
index_name = "amos-entity-knowledge"  # Single index for ALL entities

# Problem: One index must hold ALL customer data
```

**Option 2: Index-per-entity with Serverless - RECOMMENDED FOR PROPRIETARY DATA** ⭐
```ruby
# Each entity gets own index (Pinecone Serverless)
index_name = "amos-entity-#{entity.id}"
namespace = app_name  # Optional: can further subdivide by app

# ✅ Pros:
# - Maximum security isolation (separate indexes = separate databases)
# - Cost-effective with Serverless ($0.025/GB + $0.03 per 1M queries)
# - Easy customer deletion (just delete their index)
# - Regulatory compliance ready (HIPAA, SOC2)
# - No cross-contamination risk

# ⚠️ Cons:
# - Index creation takes 30-60 seconds per customer
# - Management overhead (1000 customers = 1000 indexes)

# Cost example for 1000 customers:
# - 10K vectors each × 1536 dimensions = ~60GB total
# - Storage: 60GB × $0.025/mo = $1.50/month
# - Queries: 100K queries × $0.03 per 1M = $3/month
# TOTAL: ~$5/month for 1000 customers!

# NOTE: Uses Pinecone SERVERLESS (not pod-based)
# Pod-based would be $70/month per index (too expensive)
```

**Option 3: Pooled Indexes (Recommended) - SCALABLE**
```ruby
# Shard entities across multiple indexes
SHARD_SIZE = 100  # entities per index
shard_id = (entity.id / SHARD_SIZE).floor
index_name = "amos-entity-pool-#{shard_id}"
namespace = "entity_#{entity.id}_#{app_name}"

# Example:
# Entities 1-100   → amos-entity-pool-0
# Entities 101-200 → amos-entity-pool-1
# Entities 201-300 → amos-entity-pool-2

# Pros:
# - Scales to millions of entities
# - Cost grows linearly: 100 entities = $70, 1000 entities = $700
# - Simple implementation
```

**Option 4: Dynamic Index Allocation - OPTIMAL**
```ruby
# Allocate indexes based on actual usage
class IndexAllocator
  MAX_VECTORS_PER_INDEX = 4_000_000  # Leave headroom

  def allocate_index_for_entity(entity)
    # Find index with capacity
    available_index = RagIndexPool.find_with_capacity(MAX_VECTORS_PER_INDEX)

    if available_index.nil?
      # Create new index if all full
      available_index = RagIndexPool.create_new_index!
    end

    available_index
  end
end

# Pros:
# - Optimal utilization (no wasted space)
# - Cost-effective (only pay for indexes you need)
# - Handles varying entity sizes (some have 100 docs, some have 10)
# Cons:
# - Requires index management logic
```

### Recommended Architecture Change

**Immediate (before 100 customers):**
```ruby
# app/services/rag_store_service.rb
ENTITIES_PER_INDEX = 100

def determine_index_name(entity)
  return SYSTEM_INDEX if store_type == 'system'

  shard_id = (entity.id / ENTITIES_PER_INDEX).floor
  "amos-entity-pool-#{shard_id}"
end
```

**Long-term (at scale):**
```ruby
# Create RagIndexPool model
# Migration:
create_table :rag_index_pools do |t|
  t.string :index_name, null: false
  t.integer :vector_count, default: 0
  t.integer :max_vectors, default: 4_000_000
  t.string :status, default: 'active'  # active, full, archived
end

# Track which entities are in which index
add_column :rag_stores, :index_pool_id, :bigint
add_index :rag_stores, :index_pool_id
```

---

## Intake Process (How Data Gets In)

### Scout Redis Memory Intake

**Automatic - No User Action Required**

```
1. User sends message in Scout chat
   ↓
2. scout_controller.rb receives message
   ↓
3. save_scout_message(role, content, metadata)
   ├── Saves to PostgreSQL (scout_messages table)
   └── Saves to Redis (Scout::MemoryTools.store_message)
   ↓
4. Available immediately for retrieval
```

**Code:**
```ruby
# app/controllers/scout_controller.rb
def save_scout_message(role, message, metadata: {})
  # PostgreSQL (permanent)
  ScoutMessage.create!(
    session_id: session_id,
    role: role,
    content: message,
    metadata: metadata
  )

  # Redis (fast access, 2-hour TTL)
  begin
    memory = Scout::MemoryTools.new(session_id)
    memory.store_message(role, message, metadata)
  rescue => e
    Rails.logger.warn "Redis storage failed: #{e.message}"
    # Graceful degradation - PostgreSQL still works
  end
end
```

**User Experience:** Completely transparent. Every message is automatically stored.

---

### Docling RAG Intake

**Manual - User Must Upload Documents**

#### Method 1: Scout AI Upload (Recommended)

```
1. User clicks "Upload" in Scout chat
   ↓
2. Selects file (PDF, DOCX, TXT, MD)
   ↓
3. Scout processes in background:
   ├── Docling converts to Markdown
   ├── Chunks document (semantic or simple)
   ├── Generates embeddings (with cache)
   ├── Stores in Pinecone
   └── Creates RagStore record
   ↓
4. Available for query_rag_store tool
```

**Code:**
```ruby
# User clicks upload in Scout UI
# File sent to scout_controller.rb

def handle_file_upload
  file = params[:file]

  # Process async
  ProcessDocumentJob.perform_later(
    file_path: file.path,
    entity_id: current_entity.id,
    user_id: current_user.id,
    app_name: "custom_upload"
  )
end

# Job processes document
class ProcessDocumentJob
  def perform(file_path:, entity_id:, user_id:, app_name:)
    # 1. Load document
    loader = RagLoaderService.new
    result = loader.load_document(file_path)

    # 2. Create RAG store
    rag_service = RagStoreService.new
    rag_service.create_rag_store(
      app_name,
      result[:chunks],
      {
        entity: Entity.find(entity_id),
        user: User.find(user_id),
        source: file_path,
        name: File.basename(file_path)
      }
    )
  end
end
```

#### Method 2: Admin Upload (Bulk)

```
1. Admin navigates to /admin/rag_stores
   ↓
2. Uploads multiple files or ZIP
   ↓
3. Selects chunking strategy (simple vs semantic)
   ↓
4. Assigns to entity or marks as system knowledge
   ↓
5. Batch processing begins
```

#### Method 3: API Integration (Programmatic)

```ruby
# For integrations or automated workflows
POST /api/v1/rag_stores
{
  "app_name": "product_docs",
  "content": "...",  # or "file_url": "https://..."
  "metadata": {
    "store_type": "entity",
    "name": "Product Documentation v2.1"
  }
}
```

#### Method 4: System Knowledge (One-Time Setup)

```ruby
# Admin seeds shared knowledge (Stripe docs, HubSpot docs)
rails console

loader = RagLoaderService.new
chunks = loader.load_document("docs/stripe_api_reference.pdf")

rag = RagStoreService.new
rag.create_rag_store(
  "stripe",
  chunks,
  {
    store_type: 'system',  # Available to all entities
    name: "Stripe API Reference"
  }
)
```

---

### Intake Comparison

| Feature | Scout Redis Memory | Docling RAG |
|---------|-------------------|-------------|
| **Trigger** | Automatic | Manual upload |
| **Frequency** | Every message | As needed |
| **User Action** | None required | Must upload files |
| **Processing** | Instant | 2-30 seconds (async) |
| **Batch Support** | N/A | Yes (bulk upload) |
| **API Available** | No | Yes |
| **Admin Interface** | No | Yes |

---

### Current Workflow Example

**Scenario: New customer onboarding**

```
Step 1: Customer signs up
├── Redis memory: Auto-enabled (no setup)
└── RAG: Empty (no documents yet)

Step 2: Customer uploads product documentation
├── Scout UI: "Upload" button in chat
├── Files: product_spec.pdf, api_docs.pdf, faq.docx
└── Processing: 15 seconds total
    ├── Docling converts PDFs → Markdown
    ├── Semantic chunking: 3 docs → 47 chunks
    ├── Embeddings: 47 chunks → $0.0047 cost
    └── Pinecone storage: entity_42_product_docs namespace

Step 3: Customer asks Scout a question
├── "What's our API rate limit?"
├── Scout uses query_rag_store → Searches uploaded docs
└── Finds answer in api_docs.pdf chunk #12

Step 4: Customer references earlier in conversation
├── "Earlier you mentioned 1000 req/hour - can you explain more?"
├── Scout uses search_history(keywords: "1000 req/hour")
└── Finds the message from Step 3, provides context
```

---

### Recommendations for Production

1. **Implement Index Sharding NOW** (before 100 customers)
   ```ruby
   # Add to rag_store_service.rb
   ENTITIES_PER_SHARD = 100

   def determine_index_name(entity, store_type)
     return SYSTEM_INDEX if store_type == 'system'

     shard_id = (entity.id / ENTITIES_PER_SHARD).floor
     "amos-entity-pool-#{shard_id}"
   end
   ```

2. **Add User-Friendly Upload UI**
   - Drag-and-drop file upload in Scout chat
   - Progress indicator during processing
   - List of uploaded documents in settings
   - Ability to delete/re-upload documents

3. **Add Usage Monitoring**
   ```ruby
   # Track per-entity RAG usage
   class RagUsageTracker
     def track(entity_id, operation)
       # Log: queries, storage, costs
       # Alert if approaching limits
     end
   end
   ```

4. **Implement RAG Quota System**
   ```ruby
   # Prevent abuse
   class EntityQuota < ApplicationRecord
     # max_documents: 100
     # max_vectors: 50000
     # monthly_query_limit: 10000
   end
   ```

5. **Add Cost Attribution**
   ```ruby
   # Track costs per entity
   add_column :rag_stores, :embedding_cost, :decimal
   add_column :rag_stores, :storage_cost_monthly, :decimal

   # Bill customers based on usage
   ```

---

## Related Documentation

- [Scout Memory Testing Guide](SCOUT_MEMORY_TESTING_GUIDE.md)
- [Docling Setup Guide](DOCLING_SETUP.md)
- [Docling RAG Implementation](DOCLING_AND_MULTI_TENANT_RAG_IMPLEMENTATION.md)
- [Agent Architecture](AGENT_ARCHITECTURE.md)
