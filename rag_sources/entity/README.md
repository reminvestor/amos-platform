# Entity RAG Sources

## Important: Entity Docs Are NOT Stored Here

**Entity-specific RAG documents are uploaded via Scout and stored in the database, NOT in this directory.**

This folder exists only for organizational clarity in the `rag_sources/` structure.

## How Entity RAG Works

### Upload Method
Entity customers upload documents through Scout:
- **User**: "Load my brand guidelines into RAG"
- **Scout**: Processes the uploaded file and creates an entity-scoped RAG store
- **Storage**: Database + Pinecone (isolated by entity_id)

### Security Model
- **Strict Isolation**: Each entity can ONLY access their own RAG stores
- **No Cross-Entity Access**: Entity A cannot query Entity B's documents
- **System RAG Sharing**: All entities can access system RAG stores (AMOS docs, integration docs)

### Database Storage
```ruby
RagStore (database table)
├── store_type: 'entity'
├── entity_id: <customer's entity ID>
├── user_id: <uploader's user ID>
├── name: "Brand Guidelines"
├── app_name: "Custom"
├── pinecone_index: "amos-rag-prod"
├── pinecone_namespace: "entity-123-abc123"
└── metadata: { source_files: [...], upload_date: ... }
```

### Accessing Entity RAG

#### Via Scout (User-Facing)
```
User: "What does our brand guide say about logo usage?"
Scout: *Queries entity-scoped RAG store → Returns answer*
```

#### Via Rails Console
```ruby
# Get entity's RAG stores
entity = Entity.find(1)
stores = RagStore.entity_stores(entity)

# Query entity RAG
rag_service = RagStoreService.new
result = rag_service.query_rag_store(
  store.id,
  "What are our brand colors?",
  current_entity: entity
)
```

#### Via Rake Tasks
```bash
# List all entity RAG stores
docker compose exec web rails rag:list

# Test query with entity scoping
docker compose exec web rails rag:test_query[1,"Custom","brand colors"]

# Check access permissions
docker compose exec web rails rag:check_access[1,5]
```

## Supported Upload Formats

Entity customers can upload:
- **Documents**: PDF, DOCX, PPTX
- **Text Files**: TXT, MD
- **Max Size**: 50MB per file
- **Chunk Limit**: 10,000 chunks per RAG store

## Example Entity Use Cases

1. **Brand Guidelines**
   - Logo usage rules
   - Color palettes
   - Typography standards
   - Voice & tone

2. **Product Catalogs**
   - Product descriptions
   - Specifications
   - Pricing information

3. **Internal Policies**
   - HR policies
   - Compliance documents
   - Standard operating procedures

4. **Training Materials**
   - Onboarding docs
   - Process guides
   - Best practices

## Architecture

```
┌─────────────────────────────────────────────┐
│           Scout Upload Request              │
│  "Load my brand guidelines"                 │
└──────────────┬──────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│      DocumentProcessorService               │
│  - Extracts text (Docling/fallback)        │
│  - Chunks content (semantic/fixed)         │
│  - Generates embeddings (OpenAI)           │
└──────────────┬──────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│         RagStoreService                     │
│  - Creates RagStore record (DB)            │
│  - Uploads vectors to Pinecone             │
│  - Sets entity_id for isolation            │
└──────────────┬──────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│  RagStore (Database) + Pinecone (Vectors)  │
│  - store_type: 'entity'                    │
│  - entity_id: 123                          │
│  - namespace: "entity-123-abc123"          │
└─────────────────────────────────────────────┘
```

## Security Considerations

### Enforced at Query Time
```ruby
# RagStore.find_accessible() enforces access control
store = RagStore.find_accessible(store_id, current_entity)
# Raises RecordNotFound if entity doesn't own the store
```

### Namespace Isolation
- Each entity gets a unique Pinecone namespace
- Format: `entity-{entity_id}-{random_id}`
- Prevents vector leakage between entities

### Database-Level Scoping
```ruby
# All queries automatically scope to entity
RagStore.accessible_by(entity)
  .where(store_type: 'system')         # All entities
  .or(where(store_type: 'entity', entity: entity))  # Only their docs
```

## Do NOT Store Files Here

❌ **Wrong**: Placing entity docs in this directory
```
rag_sources/entity/acme_corp/brand_guide.pdf  # ❌ WRONG
```

✅ **Correct**: Upload via Scout
```
Scout: "Load brand_guide.pdf"
→ Stored in database + Pinecone with entity_id isolation
```

## See Also

- [rag_sources/QUICK_START.md](../QUICK_START.md) - RAG system quick start
- [rag_sources/README.md](../README.md) - Full RAG documentation
- `app/models/rag_store.rb` - RagStore model code
- `app/services/rag_store_service.rb` - RAG service code
- `lib/tasks/rag.rake` - RAG rake tasks
