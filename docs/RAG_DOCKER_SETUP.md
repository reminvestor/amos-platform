# RAG Setup for Container Development

Complete guide for running AMOS RAG features (Docling + Pinecone) in containers locally.

---

## 📋 Prerequisites

**API Keys Required:**
1. **AWS Bedrock** - For Claude AI (existing)
2. **OpenAI** - For RAG embeddings ($0.0001 per 1K tokens)
3. **Pinecone** - For vector storage (Free tier available)

---

## 🚀 Quick Setup Guide

### Step 1: Get OpenAI and Pinecone Keys

**OpenAI:**
1. Visit https://platform.openai.com/api-keys
2. Click "Create new secret key"
3. Copy the key (format: `sk-...`)

**Pinecone:**
1. Visit https://app.pinecone.io and sign up
2. Create a new project
3. Copy your API key from the dashboard
4. Note your environment (e.g., `us-east-1-aws`)

### Step 2: Create Pinecone Indexes

Visit https://app.pinecone.io/indexes and create TWO indexes:

**Index 1: System Knowledge**
- Name: `amos-system-knowledge`
- Dimensions: `1536`
- Metric: `cosine`
- Pod: `p1.x1` (free tier)

**Index 2: Entity Knowledge**
- Name: `amos-entity-knowledge`
- Dimensions: `1536`
- Metric: `cosine`
- Pod: `p1.x1` (free tier)

Wait ~1 minute for indexes to show "Ready" status.

### Step 3: Configure Environment

Create or update `.env` in project root:

```bash
# AWS Bedrock (existing requirement)
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_key
AWS_SECRET_ACCESS_KEY=your_secret

# OpenAI for RAG (NEW)
OPENAI_API_KEY=sk-your-key-here

# Pinecone for RAG (NEW)
PINECONE_API_KEY=your-pinecone-key
PINECONE_ENVIRONMENT=us-east-1-aws
```

### Step 4: Start Container Services

```bash
# Build and start all services
podman compose up --build

# Or run in background
podman compose up -d --build
```

This starts:
- **PostgreSQL** on port 5432
- **Redis** on port 6379
- **Rails app** on port 3000 (with Python + Docling)

### Step 5: Verify RAG Setup

```bash
# Check Docling installation
podman compose exec web python3 -c "import docling; print('✅ Docling ready')"

# Run RAG health check
podman compose exec web rails rag:health
```

Expected output:
```
🔍 RAG System Health Check
✅ Docling: Installed
✅ OpenAI: Connected
✅ Pinecone: Connected
✅ Redis: Connected
```

### Step 6: Seed System Documentation

```bash
podman compose exec web rails rag:populate_system
```

This creates shared knowledge bases for:
- Stripe API documentation
- HubSpot API documentation
- Mailgun documentation

### Step 7: Test in Scout

1. Visit http://localhost:3000
2. Sign in or create account
3. Go to Scout chat
4. Upload a PDF or ask: "What does the Stripe documentation say about subscriptions?"

---

## 🧪 Quick Tests

**Test 1: Upload and Query Document**
```bash
# In Scout UI:
1. Click upload → select test.pdf
2. Wait for processing (~5-10s)
3. Ask: "Summarize the document"
```

**Test 2: Query System Knowledge**
```bash
# In Scout chat:
"How do I create a Stripe customer using the API?"
# Scout searches Stripe RAG store automatically
```

**Test 3: Rails Console Test**
```bash
podman compose exec web rails console
```

```ruby
# Create test RAG store
user = User.first
entity = user.entity

chunks = [{ content: "Test content", metadata: { source: "test" } }]
service = RagStoreService.new

result = service.create_rag_store(
  "test-docs",
  chunks,
  { entity: entity, user: user, name: "Test" }
)

# Query it
service.query_rag_store(result[:rag_store].id, "test query")
```

---

## 🐛 Troubleshooting

### Issue: Docling Not Installing

```bash
# Rebuild without cache
podman compose build --no-cache web
podman compose up
```

### Issue: OpenAI 401 Unauthorized

1. Check `.env` has correct `OPENAI_API_KEY`
2. Restart services: `podman compose down && podman compose up`

### Issue: Pinecone Index Not Found

1. Verify indexes exist in Pinecone dashboard
2. Check names match exactly:
   - `amos-system-knowledge`
   - `amos-entity-knowledge`

### Issue: Redis Connection Refused

```bash
# Check Redis is running
podman compose ps redis
# Should show "Up"

# Restart if needed
podman compose restart redis
```

---

## 📊 Monitoring

**View logs:**
```bash
podman compose logs -f web
```

**Check RAG status:**
```bash
podman compose exec web rails rag:list
```

**Check system health:**
```bash
podman compose exec web rails rag:health
```

---

## 💰 Cost Estimates

**OpenAI Embeddings:**
- 1,000 chunks = ~$0.10
- Cached embeddings save 70%

**Pinecone Free Tier:**
- Up to 100,000 vectors
- ~100 documents (1,000 chunks each)
- Perfect for development

---

## 🔗 Related Docs

- [RAG Architecture](./MULTI_TENANT_RAG_ARCHITECTURE.md)
- [Docling Setup](./DOCLING_SETUP.md)
- [Scout Memory vs RAG](./SCOUT_MEMORY_VS_RAG_COMPARISON.md)

---

## ✅ Success Checklist

- [ ] OpenAI API key configured
- [ ] Pinecone indexes created (2)
- [ ] Podman Compose running
- [ ] `rails rag:health` passes
- [ ] System RAG stores populated
- [ ] Scout can upload and query PDFs

**You're ready!** Visit http://localhost:3000 🎉
