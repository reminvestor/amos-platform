# Test RAG System

Runs comprehensive visual testing of the AMOS RAG (Retrieval-Augmented Generation) system including API validation, entity-scoped RAG store creation, semantic search queries, and multi-tenant isolation verification.

## What It Tests
- ✅ API key validation (OpenAI, Pinecone, Redis)
- ✅ Entity-scoped RAG store creation
- ✅ System (shared) RAG store creation
- ✅ Semantic search queries
- ✅ Multi-tenant isolation verification
- ✅ Namespace inspection
- ✅ Performance metrics
- ✅ Document upload & auto-indexing
- ✅ Real-time progress tracking via status API
- ✅ 4-stage pipeline visualization

## Prerequisites
- Docker services running: `docker-compose up -d`
- Valid `OPENAI_API_KEY` in `.env`
- Valid `PINECONE_API_KEY` in `.env`
- Pinecone indexes created:
  - `amos-system-knowledge` (1536 dimensions, cosine)
  - `amos-entity-knowledge` (1536 dimensions, cosine)
- At least one Entity exists in database

## Usage
```bash
.claude/skills/testing-rag-system/scripts/test-rag.sh
```

## Or Run Manual Tests
See the skill documentation for detailed examples including:
- **Example 4**: Document upload & progress tracking
- **Example 5**: Real-time progress monitoring via API

## Documentation
Full details available in: `.claude/skills/testing-rag-system/SKILL.md`
