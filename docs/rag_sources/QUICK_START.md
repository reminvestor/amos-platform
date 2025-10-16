# RAG Quick Start Guide

## Directory Structure

```
docs/rag_sources/
├── system/
│   ├── amos/              # 🏠 AMOS app docs (your platform documentation)
│   │   ├── architecture/  # Architecture guides
│   │   ├── user_guides/   # User manuals
│   │   └── api_docs/      # API documentation
│   │
│   └── integrations/      # 🔌 Third-party API docs
│       ├── stripe/        # Stripe integration docs
│       ├── hubspot/       # HubSpot integration docs
│       ├── mailgun/       # Mailgun integration docs
│       └── custom/        # Custom integrations
│
└── entity/                # 🏢 Customer-specific docs (uploaded via Scout)
```

## What Goes Where?

### AMOS Docs (`system/amos/`)
**Your application's internal documentation**

Examples:
- Architecture guides (AGENT_ARCHITECTURE.md)
- User manuals
- Feature documentation
- Development guides
- API references

**Purpose**: Help Scout answer questions about how AMOS works

### Integration Docs (`system/integrations/`)
**Third-party API documentation**

Examples:
- Stripe API PDF manuals
- HubSpot developer docs
- Mailgun API references
- Custom integration guides

**Purpose**: Help Scout answer questions about how to use integrations

### Entity Docs (Database Only)
**Customer-specific uploads** - NOT stored in this folder

Examples:
- Company brand guidelines
- Product catalogs
- Internal policies
- Custom workflows

**Purpose**: Customer-private knowledge (strict isolation)

## Loading Documents

### 1. Load AMOS Documentation

```bash
# Copy your docs to the folder
cp docs/AGENT_ARCHITECTURE.md docs/rag_sources/system/amos/architecture/
cp docs/WORKFLOW_V2_EXECUTIVE_SUMMARY.md docs/rag_sources/system/amos/architecture/
cp docs/QUICK_START.md docs/rag_sources/system/amos/user_guides/

# Load into RAG
docker-compose exec web rails rag:load_amos_docs
```

### 2. Load Integration Documentation

```bash
# Download integration docs (PDFs, etc.)
# Place in: docs/rag_sources/system/integrations/<integration_name>/

# Load all integrations
docker-compose exec web rails rag:load_integration_docs

# Load specific integration
docker-compose exec web rails rag:load_integration_docs[stripe]
```

### 3. Load from URLs (Alternative)

```bash
# Uses the built-in URL scraper for integration docs
docker-compose exec web rails rag:populate_system
```

## Verify RAG is Working

### Health Check
```bash
docker-compose exec web rails rag:health
```

Expected output:
```
Pinecone: ✅ Connected
OpenAI: ✅ Configured
RAG Stores:
  Total: 2
  Active: 2
  System: 2
  Entity: 0
Docling: ✅ Available
```

### List RAG Stores
```bash
docker-compose exec web rails rag:list
```

### Test Query
```bash
docker-compose exec web rails rag:test_query[1,"AMOS","How does the workflow engine work?"]
```

## Using RAG in Scout

Once loaded, Scout automatically accesses RAG stores:

**User**: "How do I create a campaign?"
**Scout**: *Queries AMOS RAG store → Returns answer from user_guides*

**User**: "How do I authenticate with Stripe?"
**Scout**: *Queries Stripe RAG store → Returns answer from integration docs*

## Prerequisites

Required environment variables in `.env`:

```bash
OPENAI_API_KEY=sk-your-key-here
PINECONE_API_KEY=your-pinecone-key
PINECONE_ENVIRONMENT=us-east-1
```

Without these, RAG commands will fail.

## Best Practices

1. **Organize by category** - Use subdirectories (architecture/, user_guides/, etc.)
2. **Use descriptive names** - `stripe_authentication.pdf` not `doc1.pdf`
3. **Keep docs updated** - Remove outdated versions
4. **Don't commit large files** - Add files >10MB to `.gitignore`
5. **Test after loading** - Always run `rails rag:health` after loading docs

## File Size Limits

- **Per file**: 50MB max
- **Per RAG store**: 10,000 chunks (~20MB text)
- **Supported formats**: PDF, DOCX, PPTX, Markdown, TXT

## Troubleshooting

### "No documents found"
- Check file extensions (.md, .pdf, .docx, .pptx, .txt)
- Verify files are in correct directory
- Check file permissions

### "Pinecone connection failed"
- Verify `PINECONE_API_KEY` in `.env`
- Check `PINECONE_ENVIRONMENT` matches your Pinecone region
- Restart Docker: `docker-compose restart web`

### "OpenAI API error"
- Verify `OPENAI_API_KEY` in `.env`
- Check API key is valid and has credits
- Restart Docker: `docker-compose restart web`

### Docling fails
- Optional - system falls back to standard processing
- Check Python dependencies: `docker-compose exec web python3 -c 'import docling'`

## Next Steps

1. Add API keys to `.env`
2. Copy AMOS docs to `docs/rag_sources/system/amos/`
3. Run `rails rag:load_amos_docs`
4. Test in Scout: "How does AMOS work?"
5. Add integration docs to `docs/rag_sources/system/integrations/`
6. Run `rails rag:load_integration_docs`
7. Test in Scout: "How do I use Stripe?"
