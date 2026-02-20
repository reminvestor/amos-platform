# RAG Configuration: Quick Reference Checklist

**Copy-paste configuration for development with LocalStack and production with AWS.**

---

## Development Setup (LocalStack)

### 1. Copy this to your `.env` file

```env
# ===== AWS Configuration (LocalStack) =====
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
AWS_S3_ENDPOINT=http://localhost:4566

# ===== RAG Storage =====
RAG_BUCKET=agent-marketing-rag-storage

# ===== OpenAI (REQUIRED - Get from https://platform.openai.com/api-keys) =====
OPENAI_API_KEY=sk-your-real-key-here
OPENAI_EMBEDDING_MODEL=text-embedding-ada-002

# ===== Bedrock Models (REQUIRED - Uses real AWS account for Bedrock) =====
# Note: LocalStack doesn't emulate Bedrock, so you need real AWS credentials
# These can be the same as above, or different AWS account
BEDROCK_DEFAULT_MODEL=claude-sonnet-4-5
BEDROCK_CHAT_MODEL=claude-sonnet-4-5
BEDROCK_VOICE_MODEL=claude-3-haiku

# ===== RAG Configuration =====
RAG_CHUNKING_STRATEGY=semantic
RAG_CHUNK_SIZE=1000
RAG_CHUNK_OVERLAP=200
RAG_EMBEDDING_CACHE_ENABLED=true
RAG_EMBEDDING_BATCH_SIZE=100

# ===== Document Processing =====
OCR_PROVIDER=auto
OCR_DOCLING_MAX_SIZE_MB=5
DOCLING_ENABLED=true

# ===== Redis (Optional - speeds up embedding caching) =====
REDIS_URL=redis://localhost:6379
```

### 2. Start LocalStack

```bash
# Starts: PostgreSQL, Redis, LocalStack
docker compose up -d

# Wait for LocalStack to be ready (should see S3 bucket created)
docker compose logs localstack | grep -i "✅\|created"
```

### 3. Start Rails

```bash
bin/dev
```

### 4. Test RAG

```bash
# Via Rails console
rails runner 'RagConfig.log_config'

# Output should show:
# 📊 RAG Configuration:
#   Chunking: semantic (size: 1000, overlap: 200)
#   Embedding: text-embedding-ada-002 (batch: 100, cache: true)
```

---

## Production Setup (AWS)

### 1. Copy this to your production `.env`

```env
# ===== AWS Configuration (REAL AWS) =====
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

# DO NOT SET AWS_S3_ENDPOINT - this forces use of real AWS S3

# ===== RAG Storage =====
RAG_BUCKET=agent-marketing-rag-storage

# ===== OpenAI (REQUIRED) =====
OPENAI_API_KEY=sk-your-production-key-here
OPENAI_EMBEDDING_MODEL=text-embedding-ada-002

# ===== Bedrock Models (REQUIRED) =====
BEDROCK_DEFAULT_MODEL=claude-sonnet-4-5
BEDROCK_CHAT_MODEL=claude-sonnet-4-5
BEDROCK_VOICE_MODEL=claude-3-haiku

# ===== RAG Configuration =====
RAG_CHUNKING_STRATEGY=semantic
RAG_CHUNK_SIZE=1000
RAG_CHUNK_OVERLAP=200
RAG_EMBEDDING_CACHE_ENABLED=true
RAG_EMBEDDING_BATCH_SIZE=100

# ===== Document Processing =====
OCR_PROVIDER=auto
OCR_TEXTRACT_PREFERRED_TYPES=invoice,receipt,form,id
TEXTRACT_ENABLED=true

# ===== Redis (ElastiCache) =====
REDIS_URL=redis://elasticache-endpoint.cache.amazonaws.com:6379

# ===== Database (RDS with pgvector) =====
DATABASE_URL=postgres://user:password@rds-endpoint.rds.amazonaws.com:5432/amos_production
```

### 2. Create AWS S3 Bucket

```bash
# Create the bucket
aws s3 mb s3://agent-marketing-rag-storage --region us-east-1

# Enable versioning (optional, for recovery)
aws s3api put-bucket-versioning \
  --bucket agent-marketing-rag-storage \
  --versioning-configuration Status=Enabled

# Verify bucket exists
aws s3 ls s3://agent-marketing-rag-storage
```

### 3. Create IAM User (Recommended)

Don't use root AWS credentials. Create an IAM user with limited permissions:

```bash
# Via AWS Console:
# 1. IAM > Users > Create user
# 2. Attach policy: S3FullAccess + BedrockFullAccess
# 3. Generate access key
# 4. Use the credentials in .env
```

### 4. Deploy

```bash
# 1. Set environment variables
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
# ... other vars from .env

# 2. Run migrations
rails db:migrate

# 3. Start application
# Use your deployment method (Heroku, ECS, etc.)
```

---

## Key Differences: LocalStack vs AWS

| Setting | LocalStack | AWS |
|---------|-----------|-----|
| `AWS_S3_ENDPOINT` | `http://localhost:4566` | **DELETE THIS LINE** |
| `AWS_ACCESS_KEY_ID` | `test` | Your actual AWS key |
| `AWS_SECRET_ACCESS_KEY` | `test` | Your actual AWS secret |
| Bedrock Access | Uses real AWS (not emulated) | Uses real AWS |
| S3 Bucket | Auto-created in `/containers/localstack/init.d/01-s3-bucket-init.sh` | Must create manually with `aws s3 mb` |
| PostgreSQL | Local container | AWS RDS |
| Redis | Local container | AWS ElastiCache |

---

## Verification Checklist

### LocalStack Development ✅

- [ ] `docker compose ps` shows all services running
- [ ] `docker compose logs localstack | grep "created"` shows bucket created
- [ ] `.env` has `AWS_S3_ENDPOINT=http://localhost:4566`
- [ ] `.env` has valid `OPENAI_API_KEY`
- [ ] `.env` has valid `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` (for Bedrock)
- [ ] `rails runner 'RagConfig.log_config'` runs without errors
- [ ] Can upload file to Scout chat and it processes without errors

### AWS Production ✅

- [ ] `.env` does NOT have `AWS_S3_ENDPOINT`
- [ ] `.env` has real AWS credentials
- [ ] S3 bucket exists: `aws s3 ls s3://agent-marketing-rag-storage`
- [ ] RDS database is running and accessible
- [ ] ElastiCache Redis is running (if using)
- [ ] IAM user has S3 + Bedrock permissions
- [ ] CloudWatch logs show successful requests

---

## Common Errors & Fixes

### "AWS credentials not found"

**Development**:
```bash
# Check .env
grep AWS .env

# Should show:
# AWS_ACCESS_KEY_ID=test
# AWS_SECRET_ACCESS_KEY=test
```

**Production**:
```bash
# Check if credentials are set
aws sts get-caller-identity

# Should output your AWS account ID
```

### "S3 bucket not found"

**LocalStack**:
```bash
# Restart LocalStack to trigger initialization
docker compose restart localstack

# Or manually create
docker compose exec localstack awslocal s3 mb s3://agent-marketing-rag-storage
```

**AWS**:
```bash
# Create bucket
aws s3 mb s3://agent-marketing-rag-storage --region us-east-1

# Verify
aws s3 ls s3://agent-marketing-rag-storage
```

### "OpenAI API error"

```bash
# Check API key is set
echo $OPENAI_API_KEY

# Test API connection
curl -H "Authorization: Bearer $OPENAI_API_KEY" \
  https://api.openai.com/v1/models

# Check rate limits in OpenAI dashboard
# https://platform.openai.com/account/billing/limits
```

### "Bedrock access denied"

```bash
# Check AWS credentials work
aws sts get-caller-identity

# Check Bedrock access
aws bedrock list-foundation-models --region us-east-1

# Verify IAM user has BedrockFullAccess policy
```

---

## Environment Variables Explained

| Variable | Purpose | Example | Required? |
|----------|---------|---------|-----------|
| `AWS_REGION` | AWS region for Bedrock, S3 | `us-east-1` | ✅ Yes |
| `AWS_ACCESS_KEY_ID` | AWS credentials | `test` (dev) | ✅ Yes |
| `AWS_SECRET_ACCESS_KEY` | AWS credentials | `test` (dev) | ✅ Yes |
| `AWS_S3_ENDPOINT` | LocalStack endpoint | `http://localhost:4566` | ⚠️ Dev only |
| `RAG_BUCKET` | S3 bucket name | `agent-marketing-rag-storage` | ✅ Yes |
| `OPENAI_API_KEY` | OpenAI embeddings | `sk-...` | ✅ Yes |
| `OPENAI_EMBEDDING_MODEL` | Embedding model | `text-embedding-ada-002` | ✅ Yes |
| `BEDROCK_DEFAULT_MODEL` | Bedrock model | `claude-sonnet-4-5` | ✅ Yes |
| `BEDROCK_CHAT_MODEL` | Chat model | `claude-sonnet-4-5` | ✅ Yes |
| `RAG_CHUNKING_STRATEGY` | Chunking method | `semantic` | ⚠️ Optional |
| `RAG_CHUNK_SIZE` | Chunk size (tokens) | `1000` | ⚠️ Optional |
| `RAG_EMBEDDING_CACHE_ENABLED` | Cache embeddings | `true` | ⚠️ Optional |
| `REDIS_URL` | Redis connection | `redis://localhost:6379` | ⚠️ Optional |

---

## Next Steps

1. **Add to `.env`**: Copy the development configuration above
2. **Start services**: `docker compose up -d`
3. **Test**: `rails runner 'RagConfig.log_config'`
4. **Upload document**: Try uploading a file in Scout chat
5. **Search**: Ask a question about the uploaded document

For detailed information, see [RAG_AWS_LOCALSTACK_SETUP.md](./RAG_AWS_LOCALSTACK_SETUP.md)
