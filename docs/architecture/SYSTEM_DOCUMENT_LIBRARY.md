# System Document Library

## Overview

The System Document Library provides a web-based admin interface for uploading and managing system-wide knowledge base documents. These documents are automatically indexed into **System RAG** stores and become queryable by all entities via Scout.

**Key Features:**
- ✅ Upload documents via web UI (no code commits required)
- ✅ Automatic indexing pipeline (Docling → Chunking → Embeddings)
- ✅ System-wide access (all entities can query these documents)
- ✅ S3 storage with organized folder structure
- ✅ Background job processing with retry logic
- ✅ Status tracking (pending → processing → indexed/failed)
- ✅ Re-indexing capability for document updates
- ✅ Works with LocalStack (local) and AWS S3 (production)

## Use Cases

### 1. **API Documentation**
Upload third-party API documentation (Stripe, HubSpot, Mailgun) so Scout can help users integrate with external services.

**Example:** Upload `stripe_api_reference_v2024.pdf`
- **Category:** `api_docs`
- **Subcategory:** `stripe`
- **Result:** Scout can answer "How do I create a Stripe customer?" by querying the uploaded API docs

### 2. **Platform Help Articles**
Upload AMOS platform guides, FAQs, and troubleshooting documents.

**Example:** Upload `campaign_creation_guide.md`
- **Category:** `help_support`
- **Subcategory:** `campaigns`
- **Result:** Scout can walk users through creating email campaigns using the guide

### 3. **Integration Guides**
Upload setup instructions for connecting third-party services.

**Example:** Upload `hubspot_integration_setup.pdf`
- **Category:** `integrations`
- **Subcategory:** `hubspot`
- **Result:** Scout can help users configure HubSpot connections

### 4. **Internal Architecture Docs**
Upload technical documentation for developers working on AMOS.

**Example:** Upload `workflow_v2_architecture.md`
- **Category:** `amos_platform`
- **Subcategory:** `architecture`
- **Result:** Scout can answer questions about the V2 workflow system

## Upload Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    Admin Uploads Document                       │
│                  /admin/system_documents/new                    │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│               File Uploaded to S3 (RAG_BUCKET)                  │
│         system/{category}/{subcategory}/{filename}              │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│             SystemDocument Record Created                       │
│                   status: pending                               │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│          SystemDocumentIndexJob Enqueued                        │
│              (background processing)                            │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Job Downloads from S3                         │
│                 status: processing                              │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│              Creates RagStore (type: 'system')                  │
│                entity_id: nil (system-wide)                     │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│          Creates RagDocument + Metadata                         │
│        (category, subcategory, uploaded_by)                     │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│         Triggers Rag::DocumentPipelineJob                       │
│    (Docling → Chunking → Embeddings → pgvector)                │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│      SystemDocument Marked as Indexed                           │
│   status: indexed, chunk_count: N, indexed_at: timestamp        │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│          Document Queryable via Scout                           │
│        HybridRagQueryService (include_system: true)             │
└─────────────────────────────────────────────────────────────────┘
```

## How to Upload Documents

### 1. Access the Admin Interface

Navigate to: **`/admin/system_documents`**

**Requirements:**
- Must be logged in as an admin user
- Access via `require_admin!` before_action

### 2. Click "Upload Document"

Redirects to: **`/admin/system_documents/new`**

### 3. Fill Out the Form

**Required Fields:**

- **Category** (dropdown)
  - `amos_platform` - AMOS product docs, architecture, guides
  - `integrations` - Third-party service docs (Stripe, HubSpot, etc.)
  - `help_support` - Help articles, FAQs, troubleshooting
  - `api_docs` - API references and technical documentation

- **Subcategory** (text field, shown for integrations/api_docs)
  - Examples: `stripe`, `hubspot`, `mailgun`, `authentication`, `campaigns`
  - Used for organizing related documents

- **File** (file picker)
  - Supported formats: PDF, DOCX, MD, TXT, PPTX
  - Maximum size: 50MB
  - Files are validated on upload

- **Description** (optional textarea)
  - Helps admins understand document purpose
  - Not included in RAG indexing (metadata only)

### 4. Submit

- File uploaded to S3: `system/{category}/{subcategory}/{filename}`
- Filename includes timestamp for uniqueness: `stripe_api_v2024_1761696847.pdf`
- SystemDocumentIndexJob automatically enqueued
- Status badge shows "Pending" → "Processing..." → "Indexed" or "Failed"

## Database Schema

### `system_documents` Table

```ruby
create_table :system_documents do |t|
  # File identification
  t.string :filename, null: false
  t.string :original_filename, null: false
  t.integer :file_size_bytes, null: false
  t.string :content_type, null: false

  # Organization
  t.string :category, null: false
  t.string :subcategory
  t.text :description

  # S3 Storage
  t.string :s3_key, null: false, unique: true

  # Processing status
  t.string :status, default: 'pending', null: false
  t.text :error_message

  # Associations
  t.references :rag_store, foreign_key: true, null: true
  t.references :uploaded_by, foreign_key: { to_table: :users }, null: false

  # Indexing metadata
  t.datetime :indexed_at
  t.integer :chunk_count, default: 0
  t.jsonb :metadata, default: {}

  t.timestamps
end
```

**Indexes:**
- `category`
- `[category, subcategory]` (composite)
- `status`
- `s3_key` (unique)

## S3 Storage Structure

### Bucket: `RAG_BUCKET` (environment variable)

```
s3://your-rag-bucket/
└── system/
    ├── amos_platform/
    │   ├── architecture/
    │   │   ├── workflow_v2_guide_1761696001.pdf
    │   │   └── agent_system_overview_1761696045.md
    │   └── features/
    │       └── campaign_management_1761696123.pdf
    ├── integrations/
    │   ├── stripe/
    │   │   ├── stripe_api_reference_1761696234.pdf
    │   │   └── stripe_webhooks_guide_1761696278.md
    │   ├── hubspot/
    │   │   └── hubspot_crm_api_1761696345.pdf
    │   └── mailgun/
    │       └── mailgun_email_api_1761696412.pdf
    ├── help_support/
    │   ├── campaigns/
    │   │   └── creating_campaigns_faq_1761696501.md
    │   └── contacts/
    │       └── importing_contacts_guide_1761696567.pdf
    └── api_docs/
        ├── rest_api/
        │   └── amos_rest_api_v1_1761696634.pdf
        └── webhooks/
            └── webhook_reference_1761696701.md
```

### S3 Key Format

```
system/{category}/{subcategory}/{timestamped_filename}
```

**Examples:**
- `system/integrations/stripe/stripe_api_reference_1761696847.pdf`
- `system/help_support/campaigns/creating_campaigns_faq_1761696901.md`
- `system/amos_platform/architecture/workflow_guide_1761696956.pdf`

## Background Job Processing

### Queue: `documents`

**Configuration** (from `config/queue.yml`):
```yaml
- queues: documents
  threads: 3
  processes: <%= ENV.fetch("DOCUMENT_WORKERS", 1) %>
  polling_interval: 0.5
  priority: 5
```

### SystemDocumentIndexJob

**Purpose:** Orchestrates the complete indexing pipeline

**Job Details:**
- **Queue:** `documents`
- **Retry:** 3 attempts with `polynomially_longer` backoff
- **Discard:** `ActiveRecord::RecordNotFound` (document was deleted)

**Processing Steps:**

1. **Download from S3**
   ```ruby
   s3_client.get_object(bucket: ENV['RAG_BUCKET'], key: s3_key).body.read
   ```

2. **Create Temp File**
   ```ruby
   temp = Tempfile.new(['system_doc', ext])
   temp.write(content)
   ```

3. **Create RagStore**
   ```ruby
   RagStore.create!(
     name: "#{category.titleize} - #{original_filename}",
     app_name: category,
     entity: nil,  # System stores have no entity
     store_type: 'system',
     status: 'pending'
   )
   ```

4. **Create RagDocument**
   ```ruby
   RagDocument.create!(
     rag_store: rag_store,
     original_filename: original_filename,
     file_size_bytes: file_size_bytes,
     content_type: content_type,
     file_hash: Digest::SHA256.file(file_path).hexdigest,
     docling_metadata: {
       category: category,
       subcategory: subcategory,
       uploaded_by: uploaded_by_id,
       system_document_id: id
     }
   )
   ```

5. **Trigger Document Pipeline**
   ```ruby
   Rag::DocumentPipelineJob.perform_now(
     file_path: file_path,
     rag_store_id: rag_store.id,
     rag_document_id: rag_document.id
   )
   ```

6. **Mark as Indexed**
   ```ruby
   system_doc.mark_indexed!(rag_store, rag_store.rag_chunks.count)
   ```

### Error Handling

If processing fails:
- Status set to `failed`
- Error message stored (truncated to 1000 chars)
- Retry logic kicks in (up to 3 attempts)
- Admin can manually re-index via UI

## Querying System Documents via Scout

System documents are automatically included in Scout queries when users ask questions.

### HybridRagQueryService Integration

```ruby
service = HybridRagQueryService.new(entity)
results = service.query(
  "How do I create a Stripe customer?",
  top_k: 10,
  include_system: true  # Default is true
)
```

### Query Behavior

**Entity + System Search:**
1. Searches entity-specific RAG stores (entity_id matches)
2. Searches system RAG stores (entity_id = nil, store_type = 'system')
3. Merges results with weighted scoring (70% vector, 30% keyword)
4. Returns top K results sorted by relevance

**Example:**

User asks: *"How do I integrate with Stripe?"*

Scout queries:
- Entity stores: User's uploaded documents ✅
- System stores: `system/integrations/stripe/stripe_api_reference.pdf` ✅
- Returns combined results with sources

### Source Attribution

Scout shows which documents were used to answer the question:

```
📖 SOURCES (2)
  📄 stripe_api_reference.pdf - System RAG • Page 12
  📄 integration_guide.pdf - Your Documents • Page 3
```

Users can click sources to view the original documents.

## Admin UI Features

### Document List View

**Stats Dashboard:**
- Total documents count
- Storage used (human-readable)
- Indexed count (green badge)
- Processing count (yellow badge)
- Failed count (red badge)

**Category Sidebar:**
- All Documents (total count)
- Expandable categories with subcategories
- Document counts per category/subcategory
- Active state highlighting

**Document Cards:**
- File icon (PDF, Word, Markdown)
- Original filename
- Category → Subcategory breadcrumb
- File size (human-readable)
- Upload time (relative, e.g., "3 hours ago")
- Uploaded by (user email)
- Description (if provided)
- Status badge with icon
- Chunk count (if indexed)
- Error message (if failed)

**Actions:**
- View (show document details)
- Download (S3 pre-signed URL, 5-minute expiry)
- Re-index (trigger new indexing job)
- Delete (removes from S3 + RAG store + database)

### Upload Form

**File Picker:**
- Accept: `.pdf,.docx,.doc,.md,.txt,.pptx`
- Max size: 50MB
- Client-side validation

**Dynamic Subcategory Field:**
- Shown when category is `integrations` or `api_docs`
- Hidden for other categories
- JavaScript toggle on category change

**Help Text:**
- File format requirements
- Category descriptions
- Processing pipeline explanation

## Environment Configuration

### Required Environment Variables

```bash
# AWS S3 Configuration (Required for document storage)
RAG_BUCKET=your-rag-bucket-name
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_access_key_id
AWS_SECRET_ACCESS_KEY=your_secret_access_key

# Optional: LocalStack for local development
AWS_S3_ENDPOINT=http://localhost:4566
```

### Local Development with LocalStack

```bash
# compose.yaml includes LocalStack service
docker compose up -d

# LocalStack provides S3 locally
AWS_S3_ENDPOINT=http://localhost:4566
RAG_BUCKET=amos-rag-local

# Create bucket
aws --endpoint-url=http://localhost:4566 s3 mb s3://amos-rag-local
```

### Production (AWS S3)

```bash
# Comment out AWS_S3_ENDPOINT to use real S3
# RAG_BUCKET should match your actual S3 bucket name
RAG_BUCKET=amos-production-rag
```

## Re-indexing Documents

### When to Re-index

- Document failed to index (error occurred)
- Updated Docling version (better extraction)
- Changed chunking strategy
- Updated embedding model
- Want to refresh RAG store

### How to Re-index

1. Navigate to `/admin/system_documents`
2. Find the document
3. Click "Re-index" button
4. Status changes: `indexed` → `pending`
5. SystemDocumentIndexJob enqueued
6. Old RagStore preserved (new one created)
7. SystemDocument linked to new RagStore when complete

**Note:** Re-indexing creates a NEW RagStore. The old RagStore is not deleted automatically to preserve history. Admins can manually delete old RagStores if needed.

## Deleting Documents

### Delete Flow

1. Click "Delete" button (with confirmation)
2. Controller attempts:
   - Delete from S3 (`delete_object`)
   - Delete associated RagStore (cascade deletes chunks)
   - Delete SystemDocument record
3. Success: Redirect with notice
4. Failure: Redirect with error message

**Cascade Deletion:**
- SystemDocument deleted
- RagStore deleted (if linked)
- RagDocument deleted (via RagStore dependency)
- RagChunks deleted (via RagDocument dependency)
- S3 file deleted

**Error Handling:**
- If S3 key doesn't exist: Warning logged, continues
- If RagStore delete fails: Error shown to admin
- Transaction rollback prevents partial deletion

## Testing the Pipeline

### Manual Test

```bash
# 1. Start Docker containers
docker compose up -d

# 2. Check admin user exists
docker compose exec web rails runner "
  admin = User.find_by(role: 'admin')
  puts admin ? 'Admin exists: ' + admin.email : 'No admin user found'
"

# 3. Configure S3 (LocalStack for testing)
# Add to .env:
# RAG_BUCKET=amos-rag-local
# AWS_S3_ENDPOINT=http://localhost:4566

# 4. Create S3 bucket
aws --endpoint-url=http://localhost:4566 s3 mb s3://amos-rag-local

# 5. Navigate to upload page
# http://localhost:3000/admin/system_documents/new

# 6. Upload a test PDF
# Category: api_docs
# Subcategory: test
# File: sample_api_doc.pdf

# 7. Monitor job processing
docker compose exec web rails runner "
  doc = SystemDocument.last
  puts 'Status: ' + doc.status
  puts 'Chunks: ' + doc.chunk_count.to_s if doc.status_indexed?
  puts 'Error: ' + doc.error_message if doc.status_failed?
"

# 8. Test querying
docker compose exec web rails runner "
  entity = Entity.first
  service = HybridRagQueryService.new(entity)
  results = service.query('test query', include_system: true)
  puts 'Results: ' + results[:chunks].length.to_s
"
```

### Automated Test

```ruby
# test/integration/system_document_upload_test.rb
class SystemDocumentUploadTest < ActionDispatch::IntegrationTest
  test "admin can upload and index system document" do
    sign_in users(:admin)

    file = fixture_file_upload('test_api_doc.pdf', 'application/pdf')

    post admin_system_documents_path, params: {
      system_document: {
        category: 'api_docs',
        subcategory: 'test',
        description: 'Test API documentation',
        file: file
      }
    }

    assert_response :redirect
    doc = SystemDocument.last
    assert_equal 'pending', doc.status
    assert_equal 'api_docs', doc.category
    assert_match /^system\/api_docs\/test\//, doc.s3_key
  end
end
```

## Troubleshooting

### Document Stuck in "Pending"

**Cause:** Job hasn't started or queue worker not running

**Check:**
```bash
# Check SolidQueue workers
docker compose exec web rails runner "puts SolidQueue::Worker.count"

# Check pending jobs
docker compose exec web rails runner "
  puts SolidQueue::Job.where(queue_name: 'documents').where(finished_at: nil).count
"

# Manually trigger job
docker compose exec web rails runner "
  doc = SystemDocument.find(123)
  SystemDocumentIndexJob.perform_now(doc.id)
"
```

### Document Failed with Error

**Cause:** S3 error, Docling failure, or embedding error

**Check Error:**
```bash
docker compose exec web rails runner "
  doc = SystemDocument.find(123)
  puts doc.error_message
"
```

**Common Errors:**

1. **S3 Access Denied**
   - Verify `RAG_BUCKET` environment variable
   - Check AWS credentials
   - Ensure bucket exists

2. **Docling Extraction Failed**
   - PDF corrupted or unsupported format
   - Check file size (50MB limit)
   - Try re-indexing

3. **Embedding Generation Failed**
   - AWS Bedrock throttling
   - Check AWS credentials
   - Review Bedrock quota limits

**Fix:** Click "Re-index" button to retry

### S3 Upload Failed

**Cause:** Network error, credentials, or bucket doesn't exist

**Check:**
```bash
# Test S3 connection
docker compose exec web rails runner "
  s3 = Aws::S3::Client.new(
    region: ENV.fetch('AWS_REGION', 'us-east-1'),
    endpoint: ENV['AWS_S3_ENDPOINT']
  )

  begin
    s3.head_bucket(bucket: ENV['RAG_BUCKET'])
    puts '✅ S3 bucket accessible'
  rescue => e
    puts '❌ S3 error: ' + e.message
  end
"
```

### No Results When Querying

**Cause:** Document not indexed yet, or query doesn't match content

**Check:**
```bash
# Verify document indexed
docker compose exec web rails runner "
  doc = SystemDocument.find(123)
  puts 'Status: ' + doc.status
  puts 'Chunks: ' + doc.chunk_count.to_s
  puts 'RAG Store ID: ' + doc.rag_store_id.to_s
"

# Check RagStore
docker compose exec web rails runner "
  store = RagStore.find(456)
  puts 'Type: ' + store.store_type
  puts 'Chunks: ' + store.rag_chunks.count.to_s
  puts 'With embeddings: ' + store.rag_chunks.where.not(embedding: nil).count.to_s
"
```

## Performance Considerations

### S3 Upload Time

- **Small files (<1MB):** <1 second
- **Medium files (1-10MB):** 1-5 seconds
- **Large files (10-50MB):** 5-30 seconds

Upload happens synchronously during form submission, so users will see a brief loading state.

### Background Job Processing Time

- **Docling extraction:** 10-60 seconds (depends on document complexity)
- **Chunking:** 1-5 seconds
- **Embedding generation:** 5-30 seconds (depends on chunk count)
- **Total processing:** 15-90 seconds average

### Storage Costs

- **S3 storage:** ~$0.023 per GB/month (Standard tier)
- **pgvector storage:** Included with PostgreSQL (no extra cost)
- **Pinecone:** Optional, not required for system documents

**Example:** 1000 documents x 5MB avg = 5GB = ~$0.12/month S3 storage

## Security Considerations

### Access Control

- Admin-only upload interface (`require_admin!`)
- SystemDocument records track `uploaded_by` for audit trail
- S3 bucket should NOT be publicly accessible
- Pre-signed URLs for downloads (5-minute expiry)

### Data Validation

- File size limit: 50MB (prevents large uploads)
- Content type validation (only document formats)
- S3 key uniqueness (prevents overwriting)
- Filename sanitization (parameterize for URL safety)

### S3 Bucket Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::amos-rag/*",
      "Condition": {
        "StringNotEquals": {
          "s3:ExistingObjectTag/public": "true"
        }
      }
    }
  ]
}
```

System documents are PRIVATE by default.

## Future Enhancements

### Potential Improvements

1. **Batch Upload**
   - Upload multiple documents at once
   - Drag-and-drop interface
   - Bulk category assignment

2. **Document Versioning**
   - Track document updates
   - Preserve old versions
   - Diff viewer for changes

3. **Advanced Search**
   - Full-text search across documents
   - Filter by category/subcategory/status
   - Date range filters

4. **Document Preview**
   - Render PDF/DOCX in browser
   - Show extracted text
   - Highlight matching chunks

5. **Analytics Dashboard**
   - Most queried documents
   - Average query response time
   - Cache hit rate
   - Document usage trends

6. **Automatic Updates**
   - Scheduled re-indexing
   - Webhook triggers for external updates
   - Version control integration (GitHub)

7. **Access Control**
   - Entity-level access restrictions
   - Document sharing between entities
   - Public vs private documents

## Summary

The System Document Library provides a complete solution for:
- ✅ Uploading knowledge base documents via web UI
- ✅ Automatic indexing into System RAG stores
- ✅ Making documents queryable by all entities
- ✅ No code commits required for documentation updates
- ✅ Works seamlessly with existing RAG infrastructure

**Admin workflow:**
1. Navigate to `/admin/system_documents`
2. Click "Upload Document"
3. Select category, file, description
4. Submit → Background job processes automatically
5. Document becomes queryable within 1-2 minutes

**User benefit:**
- Scout can answer questions using uploaded system documentation
- No need to ask admins for information
- Always up-to-date knowledge base
- Source attribution shows where answers came from
