# How Docling Works: Local vs AWS Architecture

## Overview

This document provides a **technical deep-dive** into how Docling is integrated into the AMOS application, including the Ruby-to-Python bridge, S3 integration, background job processing, and how it differs between local and AWS deployments.

**TL;DR**: Docling runs as a subprocess in both local and AWS environments. The architecture is cloud-native and uses S3 for all document I/O, making it work identically whether you're running locally with LocalStack or on AWS.

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                   Document Upload                          │
│              (User uploads PDF via UI)                      │
└───────────────────────────┬─────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│              RagProcessingJob (Sidekiq/SolidQueue)          │
│                  (Background Job)                           │
└───────────────────────────┬─────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│        Download from S3                                     │
│  (temp_file.pdf created in /tmp)                            │
└───────────────────────────┬─────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│         DoclingBridgeService (Ruby)                         │
│  Uses Open3.capture3 to spawn subprocess                    │
└───────────────────────────┬─────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│      Python Subprocess                                      │
│      lib/docling_processor.py                               │
│                                                             │
│      • Imports docling library                              │
│      • Creates DocumentConverter with PdfPipelineOptions    │
│      • Enables OCR (optical character recognition)          │
│      • Configures TableFormer for accurate extraction       │
│      • Runs HybridChunker (semantic) or simple chunking    │
│      • Converts to markdown tables                          │
│      • Returns JSON array of chunks                         │
└───────────────────────────┬─────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│     Upload Docling Output to S3                             │
│   Key: entities/{entity_id}/docling_output/                 │
│                                                             │
│   Stores full JSON for audit trail and debugging            │
└───────────────────────────┬─────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│       Update RagDocument Metadata                           │
│                                                             │
│   • docling_metadata (version, page_count)                 │
│   • extracted_tables (table data)                          │
│   • page_count (for analytics)                             │
└───────────────────────────┬─────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│      Queue ChunkingJob                                      │
│      (Next phase: embed chunks and store in Pinecone)      │
└─────────────────────────────────────────────────────────────┘
```

---

## Code Components

### 1. Ruby-to-Python Bridge: `DoclingBridgeService`

**Location**: `app/services/docling_bridge_service.rb`

**Purpose**: Acts as the interface between Rails and the Python Docling processor

**Key Method**:
```ruby
def process_file(file_path, options = {})
  # Execute Python script via Open3.capture3 (subprocess)
  stdout, stderr, status = Open3.capture3(
    "python3",
    PYTHON_SCRIPT.to_s,           # lib/docling_processor.py
    file_path,                     # /tmp/document.pdf
    chunk_size.to_s,               # 2000
    preserve_tables.to_s,          # true
    extract_images.to_s,           # false
    chunking_strategy,             # 'simple' or 'semantic'
    chunk_overlap.to_s,            # 200
    timeout: 300                   # 5 minute timeout
  )

  # Parse JSON response
  result = JSON.parse(stdout, symbolize_names: true)

  # Return hash with success, chunks, and metadata
end
```

**Availability Check**:
```ruby
def self.available?
  # Simply checks if Python can import docling
  system("python3 -c 'import docling' 2>/dev/null")
end
```

---

### 2. Python Processor: `lib/docling_processor.py`

**Purpose**: Handles all document parsing with IBM's Docling library

**Key Configuration**:
```python
# Initialize Docling with optimized settings
pipeline_options = PdfPipelineOptions()
pipeline_options.do_ocr = True                           # Enable OCR
pipeline_options.do_table_structure = True              # Extract table structure
pipeline_options.table_structure_options.mode = \
  TableFormerMode.ACCURATE                              # Best quality

# Create converter
converter = DocumentConverter(
  format_options={
    InputFormat.PDF: PdfFormatOption(
      pipeline_options=pipeline_options
    )
  }
)

# Initialize BERT tokenizer for semantic chunking
tokenizer = AutoTokenizer.from_pretrained("bert-base-uncased")
```

**Chunking Strategies**:

1. **Semantic Chunking** (Intelligent):
   - Uses HybridChunker with BERT tokenizer
   - Token-aware (not character-based)
   - Respects document structure (heading hierarchy)
   - Configurable overlap for context preservation
   - Better for RAG (preserves semantic boundaries)

2. **Simple Chunking** (Fallback):
   - Paragraph-based splitting
   - Preserves document structure
   - Handles special item types: paragraphs, headings, sections, lists, tables, images, code
   - Configurable chunk size

**Output Format**:
```json
{
  "success": true,
  "chunks": [
    {
      "content": "Full text of chunk with preserved formatting",
      "metadata": {
        "source": "document.pdf",
        "type": "semantic_chunk",
        "page": 1,
        "heading_hierarchy": ["Chapter 1", "Section 1.1"],
        "chunk_index": 0,
        "total_chunks": 42,
        "has_table": false,
        "has_image": false,
        "has_overlap": true,
        "token_count": 1850
      }
    }
  ],
  "metadata": {
    "total_pages": 50,
    "tables_found": 3,
    "images_found": 5,
    "document_type": "pdf",
    "chunking_strategy": "semantic"
  }
}
```

---

### 3. Background Job Orchestration: `Rag::DoclingExtractionJob`

**Location**: `app/jobs/rag/docling_extraction_job.rb`

**Queue**: `:docling` (memory-intensive, limited concurrency)

**Retry Strategy**:
- StandardError: 2 attempts (30 seconds wait)
- DoclingError: 1 attempt (60 seconds wait)
- Timeout: 10 minutes per document

**Process Flow**:
```ruby
def perform(rag_document_id)
  # 1. Download document from S3 to temp file
  temp_file = download_from_s3(rag_document, rag_store)

  # 2. Check if Docling available (fallback if not)
  unless docling_available?
    queue_fallback_processor(rag_document.id)
    return
  end

  # 3. Process with Docling via DoclingBridgeService
  docling_output = process_with_docling(temp_file.path)

  # 4. Store full Docling output in S3 (for audit trail)
  docling_s3_path = store_docling_output(rag_store, rag_document, docling_output)

  # 5. Update RagDocument with metadata
  update_document_metadata(rag_document, docling_output, docling_s3_path)

  # 6. Queue next phase: ChunkingJob
  Rag::ChunkingJob.perform_later(rag_document.id)

ensure
  # Clean up temp file
  temp_file&.close!
end
```

---

## Local Deployment

### Setup
```bash
# Install Python dependencies
pip3 install -r requirements.txt

# This installs:
# - docling
# - docling-core
# - docling-ibm-models (AI models for layout analysis)
# - docling-parse
# - python-magic
# - pillow
# - pdfplumber
```

### How It Works Locally
1. **User uploads document** → Rails stores in LocalStack S3
2. **DoclingExtractionJob enqueued** → SolidQueue (in-memory or Redis)
3. **Worker downloads from LocalStack S3** → `/tmp/docling_*.pdf`
4. **DoclingBridgeService spawns Python subprocess** → `python3 lib/docling_processor.py ...`
5. **Docling processes document** → Runs on same machine/container
6. **Python outputs JSON** → captured by Open3
7. **Docling output uploaded to LocalStack S3** → for audit trail
8. **RagDocument metadata updated** → database
9. **ChunkingJob queued** → Next phase

### S3 Configuration (Local)
```ruby
# Uses LocalStack (Docker container)
bucket: 'amos-rag-storage'
endpoint: 'http://localhost:4566'  # LocalStack endpoint

# S3 paths follow same pattern as AWS
entities/#{entity_id}/docling_output/#{rag_store_id}/#{rag_document_id}_output.json
```

### Docker Compose Setup
```yaml
# compose.yaml
localstack:
  image: localstack/localstack:latest
  ports:
    - "4566:4566"  # S3, SQS, etc.
  environment:
    SERVICES: s3,sqs,dynamodb

app:
  depends_on:
    - localstack
  environment:
    AWS_S3_BUCKET: amos-rag-storage
    AWS_ENDPOINT_URL: http://localstack:4566
    AWS_ACCESS_KEY_ID: test
    AWS_SECRET_ACCESS_KEY: test
```

---

## AWS Deployment

### Setup
```bash
# Python dependencies (on EC2/ECS)
pip3 install -r requirements.txt

# Environment variables (set via secrets manager)
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=***
AWS_SECRET_ACCESS_KEY=***
RAG_BUCKET=amos-rag-storage  # Real AWS S3 bucket
```

### How It Works on AWS
1. **User uploads document** → Rails stores in AWS S3
2. **DoclingExtractionJob enqueued** → SolidQueue (Redis)
3. **ECS worker (container) downloads from S3** → `/tmp/docling_*.pdf`
4. **DoclingBridgeService spawns Python subprocess** → Same container
5. **Docling processes document** → Uses container's Python
6. **Python outputs JSON** → captured by Open3
7. **Docling output uploaded to S3** → for audit trail
8. **RagDocument metadata updated** → RDS database
9. **ChunkingJob queued** → Next phase (SQS)

### S3 Configuration (AWS)
```ruby
# Uses real AWS S3
bucket: ENV.fetch('RAG_BUCKET', 'amos-rag-storage')
# No custom endpoint needed - uses AWS SDK defaults

# Same S3 path pattern
entities/#{entity_id}/docling_output/#{rag_store_id}/#{rag_document_id}_output.json
```

### ECS Task Definition
```json
{
  "containerDefinitions": [
    {
      "name": "amos-app",
      "image": "123456789.dkr.ecr.us-east-1.amazonaws.com/amos:latest",
      "environment": [
        {
          "name": "RAG_BUCKET",
          "value": "amos-rag-storage"
        },
        {
          "name": "AWS_REGION",
          "value": "us-east-1"
        }
      ]
    }
  ]
}
```

---

## Key Differences: Local vs AWS

| Aspect | Local | AWS |
|--------|-------|-----|
| **S3 Implementation** | LocalStack (Docker) | Real AWS S3 |
| **Python Execution** | Subprocess on local machine | Subprocess in ECS container |
| **Queue System** | SolidQueue (in-memory or local Redis) | SolidQueue with Redis (ElastiCache) |
| **Database** | PostgreSQL (local) | RDS PostgreSQL |
| **Temp File Storage** | `/tmp` on local disk | `/tmp` in container (ephemeral) |
| **Scalability** | Single container | Auto-scaling with load balancer |
| **Monitoring** | Rails logs in console | CloudWatch logs |
| **Cost** | Free (local development) | Pay per API call, storage, compute |
| **Reliability** | May fail if system resources exhausted | Automatic retry via SQS, DLQ handling |

---

## Error Handling & Fallback

### When Docling Fails
```ruby
# Automatically triggered:
# 1. Docling not installed
# 2. Processing timeout (>10 minutes)
# 3. Python subprocess crash
# 4. Invalid document format
# 5. Out of memory

# Fallback job queued:
Rag::FallbackProcessorJob.perform_later(rag_document_id)

# FallbackProcessorJob uses:
# - PDF-reader gem (for PDFs)
# - Kramdown (for Markdown)
# - XLSX/DOCX parsers (basic support)
```

### Error Logs
```
❌ DoclingExtractionJob failed: Docling not available
   → Queuing FallbackProcessorJob for document #123

❌ Docling processing timed out after 10 minutes
   → Retrying (attempt 1/2)
   → If all retries fail: Fall back to FallbackProcessorJob
```

---

## Performance Characteristics

### Processing Time
- **Small PDFs** (<10 pages): ~2-5 seconds
- **Medium PDFs** (10-50 pages): ~5-15 seconds
- **Large PDFs** (>50 pages): ~30-60+ seconds
- **Scanned PDFs** (with OCR): +50% (OCR adds time)

### Memory Usage
- **Startup**: ~200 MB (Python interpreter + libraries)
- **Small PDFs**: +100-200 MB
- **Medium PDFs**: +300-500 MB
- **Large PDFs**: +500-1000+ MB

### Recommendations
- Set max file size: **50 MB**
- Use separate `:docling` queue with limited concurrency (2-3 workers)
- Monitor memory on EC2/ECS instances
- Increase timeout in staging if processing large documents

---

## Configuration

### Environment Variables
```bash
# RagConfig (from config/initializers/rag_config.rb)
RAG_CHUNKING_STRATEGY=semantic    # 'simple' or 'semantic'
RAG_CHUNK_SIZE=2000               # tokens (semantic) or chars (simple)
RAG_CHUNK_OVERLAP=200             # for semantic chunking only
RAG_BUCKET=amos-rag-storage       # S3 bucket name
```

### Settings in Code
```ruby
# app/services/docling_bridge_service.rb
PYTHON_SCRIPT = Rails.root.join("lib", "docling_processor.py")
CHUNK_SIZE = 2000
timeout: 300  # 5 minutes (DoclingBridgeService)

# app/jobs/rag/docling_extraction_job.rb
DOCLING_TIMEOUT = 10.minutes  # Background job timeout
queue_as :docling             # Separate queue for memory management
```

---

## S3 Path Strategy

### Directory Structure
```
amos-rag-storage/
├── system/                              # System RAG stores (all entities)
│   ├── stripe/
│   │   ├── raw_documents/
│   │   ├── processed/
│   │   ├── docling_output/
│   └── hubspot/
│       ├── raw_documents/
│       ├── processed/
│       └── docling_output/
│
└── entities/                            # Entity-specific RAG stores
    ├── 123/                             # Entity ID
    │   ├── custom_api/
    │   │   ├── raw_documents/
    │   │   │   └── 456/                 # RagDocument ID
    │   │   │       └── api_docs.pdf
    │   │   ├── processed/
    │   │   └── docling_output/
    │   │       └── 456_output.json      # Full Docling JSON
    │   │
    │   └── internal_docs/
    │       ├── raw_documents/
    │       ├── processed/
    │       └── docling_output/
```

### S3 Key Naming
```ruby
# Raw document (original upload)
"entities/#{entity_id}/raw_documents/#{rag_document_id}/original_filename.pdf"

# Docling full output (JSON)
"entities/#{entity_id}/docling_output/#{rag_store_id}/#{rag_document_id}_output.json"

# Processed chunks (after chunking)
"entities/#{entity_id}/processed/#{rag_store_id}/#{rag_document_id}_chunks.json"
```

---

## Testing & Debugging

### Check Docling Installation
```bash
# In Rails console
DoclingBridgeService.check_installation
# => { installed: true, version: "2.18.1", python_path: "/usr/bin/python3" }

# Or directly
python3 -c "import docling; print(docling.__version__)"
```

### Test Processing
```ruby
# Manual test in Rails console
bridge = DoclingBridgeService.new
result = bridge.process_file(
  '/path/to/document.pdf',
  chunk_size: 2000,
  preserve_tables: true,
  chunking_strategy: 'semantic'
)

puts "Success: #{result[:success]}"
puts "Chunks: #{result[:chunks].length}"
puts "Metadata: #{result[:metadata]}"
```

### Monitor Background Jobs
```bash
# Check job queue status
rails console
SolidQueue::Job.where(queue: 'docling').count

# Find specific job
job = SolidQueue::Job.find_by(job_class: 'Rag::DoclingExtractionJob')
job.inspect  # Show details, errors, retry_count

# Check failed jobs
SolidQueue::FailedExecution.recent(limit: 20)
```

### View S3 Outputs
```bash
# Local (LocalStack)
aws s3 ls s3://amos-rag-storage/entities/ \
  --endpoint-url http://localhost:4566 \
  --recursive

# AWS
aws s3 ls s3://amos-rag-storage/entities/ --recursive
```

---

## Security Considerations

### 1. Temporary Files
- Created in `/tmp` by Tempfile class
- Automatically deleted after processing
- No disk exposure on AWS (ephemeral container storage)

### 2. S3 Access
- Documents encrypted in S3 (AES256)
- Full Docling JSON stored for audit trail
- S3 paths include entity_id (multi-tenant isolation)

### 3. Process Isolation
- Python subprocess runs in isolated process
- No access to other app processes
- Memory limits enforced by OS/Docker

### 4. Timeout Protection
- 5-minute timeout prevents hung processes
- 10-minute job timeout prevents queue blocking
- Auto-cleanup via `ensure` block

---

## Future Optimizations

### Short Term
- [ ] Caching Docling results per document hash
- [ ] Batch processing multiple documents in single Python process
- [ ] Custom OCR models for specific document types
- [ ] Parallel chunking for large documents

### Long Term
- [ ] GPU acceleration for OCR (CUDA/Docker GPU support)
- [ ] Custom model fine-tuning for domain-specific documents
- [ ] Distributed processing (multiple workers in parallel)
- [ ] Image embedding for visual RAG

---

## Summary

**Local and AWS deployments are functionally identical** because:
1. Both use S3 (LocalStack locally, AWS S3 on cloud)
2. Both spawn Python subprocess the same way
3. Both use same background job queue structure
4. S3 paths and bucket structure are identical

The main differences are infrastructure (LocalStack vs AWS) and scalability (single container vs auto-scaling), not the Docling integration itself.

---

**Status**: ✅ Complete
**Last Updated**: 2025-11-05
**Related Files**:
- `lib/docling_processor.py` - Python processor
- `app/services/docling_bridge_service.rb` - Ruby bridge
- `app/jobs/rag/docling_extraction_job.rb` - Job orchestration
- `docs/DOCLING_SETUP.md` - Installation guide
- `docs/DOCLING_AND_MULTI_TENANT_RAG_IMPLEMENTATION.md` - Architecture overview
