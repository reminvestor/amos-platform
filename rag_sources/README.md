# RAG Source Documents

This directory contains source documents for the RAG (Retrieval-Augmented Generation) system.

## Directory Structure

```
rag_sources/
├── system/
│   ├── amos/              # AMOS platform documentation
│   │   ├── architecture/  # System architecture docs
│   │   ├── user_guides/   # User-facing help docs
│   │   └── api_docs/      # API documentation
│   │
│   └── integrations/      # Third-party integration docs
│       ├── stripe/        # Stripe API docs
│       ├── hubspot/       # HubSpot API docs
│       ├── mailgun/       # Mailgun API docs
│       └── custom/        # Custom integration docs
│
└── entity/                # Entity-specific RAG sources (customer uploads)
    └── README.md          # Instructions for entity RAG
```

## System RAG Sources

### AMOS Documentation (`system/amos/`)

Place AMOS platform documentation here:
- Architecture guides
- User manuals
- Feature documentation
- API references
- Best practices

**Supported formats**: PDF, DOCX, PPTX, Markdown, TXT

**Example**:
```
system/amos/architecture/
  - AGENT_ARCHITECTURE.md
  - WORKFLOW_V2_EXECUTIVE_SUMMARY.md
  - INTEGRATION_ARCHITECTURE_V2.md

system/amos/user_guides/
  - QUICK_START.md
  - EMAIL_SEQUENCE_QUICK_REFERENCE.md
```

### Integration Documentation (`system/integrations/`)

Place third-party integration docs here:
- API documentation (PDFs, DOCX)
- Authentication guides
- Webhook references
- Rate limiting docs

**Example**:
```
system/integrations/stripe/
  - stripe_api_reference.pdf
  - stripe_webhooks.pdf
  - authentication.md

system/integrations/hubspot/
  - hubspot_crm_api.pdf
  - contacts_guide.pdf
```

## Loading Documents into System RAG

### Option 1: Rake Task (Recommended)

```bash
# Load all AMOS docs
docker-compose exec web rails rag:load_amos_docs

# Load specific integration docs
docker-compose exec web rails rag:load_integration_docs[stripe]

# Load all system docs (AMOS + integrations)
docker-compose exec web rails rag:populate_system
```

### Option 2: Via Scout

1. Log in as admin
2. Say: "Load the AMOS documentation into system RAG"
3. Scout will index all docs in `system/amos/`

## Entity RAG Sources

Entity-specific documents are uploaded via Scout by individual customers and stored in the database with strict isolation. They are NOT stored in this directory.

## Best Practices

1. **Organize by category** - Keep docs well-organized in subdirectories
2. **Use descriptive filenames** - `stripe_authentication.pdf` not `doc1.pdf`
3. **Keep docs up-to-date** - Remove outdated versions
4. **Prefer official sources** - Use official API docs when possible
5. **Version control** - Commit important docs to git (except huge files)

## File Size Limits

- **Per file**: 50MB max (Docling can handle large PDFs)
- **Per RAG store**: 10,000 chunks max (~20MB of text)
- **Total system RAG**: Unlimited stores

## Git Ignore

Large binary files (>10MB) should be added to `.gitignore`. Store them externally (S3, etc.) and document how to fetch them.
