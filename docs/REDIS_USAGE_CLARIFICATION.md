# Redis Usage in AMOS: RAG vs Scout Memory

## Quick Answer

**Redis is used for TWO separate purposes:**

1. **RAG Embedding Cache** (Redis DB 0) - NEW in Phase 2
2. **Agent Memory** (Redis DB 1) - Pattern learning and decision weights

**Scout conversation history is stored in PostgreSQL** (`scout_messages` table), **NOT Redis**.

---

## Detailed Breakdown

### 1. RAG Embedding Cache (Redis DB 0)

**Purpose**: Cache OpenAI embeddings to reduce costs by 70%

**Connection**: `redis://redis:6379/0`

**What's Stored**:
```ruby
# Key: SHA256 hash of text content
# Value: 1536-dimensional embedding vector (JSON)

"embedding_cache:a3f5b2..." => "[0.1234, -0.5678, ...]"
```

**Statistics**:
```ruby
"embedding_cache:stats:hits" => "7050"
"embedding_cache:stats:misses" => "2950"
```

**Configuration**:
- Max size: 10,000 embeddings
- TTL: 30 days
- Eviction: LRU (Least Recently Used)
- Memory usage: ~65MB at full capacity

**Service**: `EmbeddingCacheService`

**Use Case**: When processing documents or querying RAG, check if we've already generated embeddings for this text. If yes, use cached embedding (free). If no, call OpenAI ($$$) and cache result.

---

### 2. Agent Memory (Redis DB 1)

**Purpose**: Store learned patterns and decision weights for agent self-improvement

**Connection**: `redis://redis:6379/1`

**What's Stored**:
```ruby
# Agent memories (patterns, successful strategies, decision weights)
"agent_memory:workflow_123" => {
  patterns: [...],
  successful_patterns: [...],
  decision_weights: { ... },
  metadata: { ... }
}
```

**Service**: `Agents::Memory::AgentMemory`

**Use Case**: When agents complete workflows, they store what worked/failed. Next time similar task runs, agent recalls past successes and adapts behavior.

**Example**:
```ruby
# Agent learns that structured approach works better for campaign creation
agent.store_long_term(:successful_patterns, {
  type: 'campaign_creation',
  approach: 'structured',
  success_rate: 0.95
})

# Next time: Agent checks memory and prefers structured approach
relevant_patterns = agent.find_relevant_patterns(task)
```

---

### 3. Scout Conversation History (PostgreSQL)

**Purpose**: Permanent record of all Scout chat conversations

**Storage**: PostgreSQL database (`scout_messages` table)

**Schema**:
```sql
CREATE TABLE scout_messages (
  id BIGINT PRIMARY KEY,
  user_id BIGINT,
  entity_id BIGINT,
  session_id STRING,
  role STRING,  -- 'user' or 'assistant'
  content TEXT,
  created_at TIMESTAMP
);
```

**What's Stored**:
- Every user message to Scout
- Every Scout response
- Session tracking (for conversation continuity)
- Entity scoping (multi-tenant isolation)

**Service**: `ScoutMessage` model

**Use Case**: When user returns to chat, Scout loads previous conversation from PostgreSQL to maintain context.

**Example**:
```ruby
# User opens Scout chat
session_messages = ScoutMessage
  .for_session(session_id)
  .oldest_first
  .limit(100)

# Scout sees previous context:
# User: "Create a campaign for Product X"
# Assistant: "I'll create that campaign. What's the target audience?"
# User: "Enterprise customers"
# ... (conversation continues)
```

---

## Why This Architecture?

### RAG Embedding Cache (Redis DB 0)

**Why Redis?**
- Fast lookup (< 1ms)
- LRU eviction handles size limits automatically
- TTL support for cache expiration
- Simple key-value storage perfect for embeddings

**Why NOT PostgreSQL?**
- Too slow for high-frequency lookups
- No built-in LRU eviction
- Embeddings are temporary (30-day TTL)

**Why NOT Pinecone?**
- Pinecone is for similarity search, not exact match lookup
- Would incur additional API costs
- Cache needs to be fast and free

### Agent Memory (Redis DB 1)

**Why Redis?**
- Fast access to learned patterns
- Persistence (survives restarts)
- Separate namespace from RAG cache
- JSON serialization support

**Why NOT PostgreSQL?**
- Agent memory is accessed frequently during workflow execution
- PostgreSQL queries would slow down agent decisions
- Redis provides faster in-memory access

### Scout Conversation History (PostgreSQL)

**Why PostgreSQL?**
- Permanent record (not cache)
- Relational queries (join with users, entities)
- Full-text search capabilities
- Audit trail requirements
- Conversation analytics

**Why NOT Redis?**
- Conversations need permanent storage
- Need to query across sessions
- Need to filter by user, entity, date range
- Redis memory limits (eviction would lose conversations)

---

## Visual Architecture

```
┌────────────────────────────────────────────────────────────┐
│                     AMOS Platform                          │
│                                                             │
│  ┌─────────────────┐                                       │
│  │  Scout Chat     │                                       │
│  │  Controller     │                                       │
│  └────────┬────────┘                                       │
│           │                                                 │
│           │ Loads conversation history                     │
│           ▼                                                 │
│  ┌─────────────────────────────┐                          │
│  │   PostgreSQL Database       │                          │
│  │  ┌─────────────────────┐    │                          │
│  │  │  scout_messages     │    │  ← Permanent Storage    │
│  │  │  - user messages    │    │                          │
│  │  │  - scout responses  │    │                          │
│  │  │  - session_id       │    │                          │
│  │  └─────────────────────┘    │                          │
│  │  ┌─────────────────────┐    │                          │
│  │  │  rag_stores         │    │  ← RAG Metadata         │
│  │  │  - app_name         │    │                          │
│  │  │  - chunk_count      │    │                          │
│  │  │  - namespace        │    │                          │
│  │  └─────────────────────┘    │                          │
│  └─────────────────────────────┘                          │
│                                                             │
│  ┌─────────────────────────────┐                          │
│  │   Redis (Multi-Database)    │                          │
│  │                             │                          │
│  │  [DB 0] RAG Embedding Cache │  ← Phase 2              │
│  │  - embedding vectors        │    70% cost savings     │
│  │  - cache statistics         │                          │
│  │  - LRU eviction             │                          │
│  │                             │                          │
│  │  [DB 1] Agent Memory        │  ← Agent Learning       │
│  │  - learned patterns         │    Self-improvement     │
│  │  - decision weights         │                          │
│  │  - successful strategies    │                          │
│  └─────────────────────────────┘                          │
│                                                             │
│  ┌─────────────────────────────┐                          │
│  │   Pinecone Vector Database  │  ← RAG Vectors          │
│  │  - Document embeddings      │    Similarity Search    │
│  │  - Metadata (pages, etc)    │                          │
│  │  - Multi-tenant namespaces  │                          │
│  └─────────────────────────────┘                          │
└────────────────────────────────────────────────────────────┘
```

---

## Configuration

### .env Setup

```bash
# Redis connection (both DB 0 and DB 1 use this)
REDIS_URL=redis://redis:6379/0

# RAG uses DB 0 explicitly
# Agent Memory uses DB 1 explicitly
```

### Service Configuration

**RAG Embedding Cache** (`EmbeddingCacheService`):
```ruby
def initialize
  @redis = Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379/0")
  # Uses DB 0
end
```

**Agent Memory** (`Agents::Memory::AgentMemory`):
```ruby
def initialize(agent_id:, role:)
  @redis = Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379/1")
  # Uses DB 1 (different namespace)
end
```

**Scout Conversation** (`ScoutMessage` model):
```ruby
# PostgreSQL ActiveRecord model
# No Redis involved
ScoutMessage.for_session(session_id).oldest_first
```

---

## Monitoring

### Check RAG Cache (Redis DB 0)

```bash
# Console
podman compose exec web rails console

# Check cache stats
service = RagStoreService.new
stats = service.cache_stats
puts stats
# => { hit_rate: 70%, total_keys: 8500, memory_usage: "52MB" }

# Direct Redis check
redis = Redis.new(url: "redis://redis:6379/0")
redis.keys("embedding_cache:*").count
# => 8500
```

### Check Agent Memory (Redis DB 1)

```bash
# Direct Redis check
redis = Redis.new(url: "redis://redis:6379/1")
redis.keys("agent_memory:*")
# => ["agent_memory:workflow_123", "agent_memory:workflow_456"]

# Check specific agent memory
redis.hkeys("agent_memory:workflow_123")
# => ["patterns", "successful_patterns", "decision_weights", "metadata"]
```

### Check Scout Conversation (PostgreSQL)

```bash
# Rails console
ScoutMessage.count
# => 15432

# Recent messages
ScoutMessage.recent_first.limit(10).pluck(:role, :content)

# Session continuity
ScoutMessage.for_session("session_abc").count
# => 25
```

---

## Memory Usage Comparison

| Storage | Purpose | Size | Eviction | Persistence |
|---------|---------|------|----------|-------------|
| Redis DB 0 (RAG Cache) | Embedding cost optimization | ~65MB | LRU (30 days) | Temporary |
| Redis DB 1 (Agent Memory) | Agent learning | ~10MB | Manual forget | Persistent |
| PostgreSQL (Scout Conversations) | Chat history | ~500MB | Never | Permanent |
| Pinecone (RAG Vectors) | Document search | ~100MB per 100K docs | Manual delete | Permanent |

---

## Common Questions

### Q: Why not use RAG for Scout conversation memory?

**A**: RAG is for **document search**, not conversation history.

- **RAG**: "Find relevant documentation about Stripe authentication"
- **Conversation**: "What did the user ask 5 messages ago?"

These are fundamentally different use cases:
- RAG uses **semantic similarity search** (vector embeddings)
- Conversation uses **chronological retrieval** (SQL ORDER BY created_at)

### Q: Could we consolidate Redis DB 0 and DB 1?

**A**: Yes, but separation is cleaner:

**Pros of separation**:
- Different eviction policies (LRU vs manual)
- Different TTLs (30 days vs permanent)
- Easier monitoring (cache stats separate from agent stats)
- Clearer architecture (explicit purpose)

**Cons of separation**:
- Slightly more complex configuration

**Verdict**: Keep separate for clarity and flexibility.

### Q: Why not cache Scout responses in Redis?

**A**: Scout responses are generated dynamically based on:
- User input (changes every time)
- Conversation context (evolves)
- RAG retrieval results (different documents)
- Tool execution outcomes (dynamic)

Caching wouldn't provide value since responses are rarely identical.

---

## Summary

**Redis DB 0** = RAG embedding cache (70% cost savings)
**Redis DB 1** = Agent pattern memory (self-improvement)
**PostgreSQL** = Scout conversation history (permanent record)
**Pinecone** = RAG vector search (document similarity)

**All four are independent and serve different purposes.**
