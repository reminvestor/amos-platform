# Docling Integration Setup

This document describes how to set up and use Docling for enhanced document processing in AMOS.

## Overview

Docling is IBM's advanced document parser that provides superior extraction capabilities compared to standard parsers, especially for:

- **Complex PDFs** with tables, multi-column layouts, headers/footers
- **Microsoft Office documents** (DOCX, PPTX, XLSX)
- **Table extraction** - preserves structure in markdown format
- **Layout analysis** - understands document hierarchy
- **OCR support** - extracts text from scanned documents

## Architecture

```
Document Upload
      ↓
DocumentProcessorService (Ruby)
      ↓
Try Docling? → Yes → DoclingBridgeService (Ruby) → docling_processor.py (Python)
      ↓                                                      ↓
      No                                            Docling Library
      ↓                                                      ↓
Standard Processing                               Enhanced Chunks
(PDF-reader, Kramdown)                                     ↓
      ↓                                                     ↓
      └──────────────────→ Chunks Array ←──────────────────┘
                                ↓
                          RagStoreService
                                ↓
                          Pinecone Vector Store
```

## Installation

### Prerequisites

- Python 3.9 or higher
- pip3 package manager
- Sufficient system resources (Docling can be memory-intensive)

### Install Docling

```bash
# From the project root
pip3 install -r requirements.txt
```

This installs:
- `docling` - Main library
- `docling-core` - Core data models
- `docling-ibm-models` - IBM's AI models for layout analysis
- `docling-parse` - Document parsing utilities
- Supporting libraries (Pillow, pdfplumber, python-magic)

### Verify Installation

```bash
# Check if Docling is installed
python3 -c "import docling; print(docling.__version__)"

# Run health check (optional, if rake task is created)
rails docling:check
```

### Optional: Virtual Environment

For isolation, use a virtual environment:

```bash
# Create virtual environment
python3 -m venv venv

# Activate it
source venv/bin/activate  # On macOS/Linux
# or
venv\Scripts\activate     # On Windows

# Install dependencies
pip install -r requirements.txt
```

## Configuration

### Environment Variables

No environment variables are required. Docling integration is automatic if the library is installed.

To disable Docling (force standard processing):

```ruby
# In your code
processor = DocumentProcessorService.new(use_docling: false)
```

### Supported File Types

Docling automatically handles:
- `.pdf` - PDF documents
- `.docx` - Microsoft Word documents
- `.pptx` - PowerPoint presentations
- `.xlsx` - Excel spreadsheets
- `.html` - HTML files
- `.md` - Markdown files
- `.asciidoc` - AsciiDoc files
- `.xml` - XML documents

## Usage

### Automatic Usage (Default)

Docling is automatically used when:
1. It's installed and available
2. A supported file type is uploaded
3. The file is being processed for RAG store creation

No code changes needed - it works transparently!

### Manual Usage

```ruby
# Process a document with Docling
bridge = DoclingBridgeService.new
result = bridge.process_file(
  '/path/to/document.pdf',
  chunk_size: 2000,
  preserve_tables: true,
  extract_images: false
)

if result[:success]
  puts "Extracted #{result[:chunks].length} chunks"
  result[:chunks].each do |chunk|
    puts "Page #{chunk[:metadata][:page]}: #{chunk[:content][0..100]}..."
  end
end
```

### Via AI Tools

Users can ask AMOS to process documents:

```
User: "Index the API documentation from this PDF"
AI: [uses create_rag_store tool → DocumentProcessorService → Docling]
```

## Fallback Behavior

The system gracefully falls back to standard processing if:

1. **Docling not installed** - Uses PDF-reader for PDFs, Kramdown for Markdown, etc.
2. **Docling processing fails** - Automatically retries with standard parser
3. **Timeout** - After 5 minutes, falls back
4. **Unsupported file** - Non-Docling files use standard processing

This ensures **zero breaking changes** - the system works with or without Docling.

## Performance Considerations

### Memory Usage

Docling can be memory-intensive for large documents:
- **Small PDFs** (<10 pages): ~100-200 MB
- **Medium PDFs** (10-50 pages): ~300-500 MB
- **Large PDFs** (>50 pages): 500+ MB

**Recommendation**: Set reasonable upload limits (e.g., 50 MB max file size).

### Processing Time

Docling is slower than standard parsers but produces better results:
- **Standard PDF-reader**: ~1-2 seconds for 10-page PDF
- **Docling**: ~5-10 seconds for 10-page PDF (includes layout analysis, OCR)

**Trade-off**: Better extraction quality vs. speed.

### Timeout

Default timeout: **5 minutes**

Adjust in `DoclingBridgeService` if needed:

```ruby
stdout, stderr, status = Open3.capture3(
  "python3",
  PYTHON_SCRIPT.to_s,
  file_path,
  timeout: 600 # 10 minutes
)
```

## Troubleshooting

### Docling Not Found

**Error**: `Docling is not available. Install with: pip3 install -r requirements.txt`

**Solution**:
```bash
pip3 install -r requirements.txt
```

### Python Version Issues

**Error**: `ModuleNotFoundError: No module named 'docling'`

**Solution**: Ensure Python 3.9+:
```bash
python3 --version  # Should be 3.9 or higher
pip3 install -r requirements.txt
```

### Memory Errors

**Error**: `MemoryError` or `Killed`

**Solution**:
- Process smaller documents
- Increase system memory
- Reduce chunk size in processing options

### Permission Errors

**Error**: `Permission denied: /path/to/file`

**Solution**: Ensure temp files have correct permissions:
```bash
chmod 644 /path/to/uploaded/file
```

### Timeout Issues

**Error**: `Processing timed out after 5 minutes`

**Solution**:
- Increase timeout in `DoclingBridgeService`
- Process document in smaller chunks
- Use standard processing for very large files

## Monitoring

### Check Docling Status

```ruby
# In Rails console
DoclingBridgeService.check_installation
# => { installed: true, version: "2.18.1", python_path: "/usr/bin/python3" }
```

### Logs

Docling processing logs include:
```
✨ Docling enabled for enhanced document processing
📄 Processing document with Docling: example.pdf
✅ Docling extracted 42 chunks
```

Fallback logs:
```
⚠️ Docling processing failed, falling back to standard processing
📄 Using standard document processing (Docling not available)
```

## Advanced Configuration

### Custom Chunk Size

```ruby
processor = DocumentProcessorService.new
result = processor.process_with_docling(
  file_path,
  filename,
  chunk_size: 3000  # Larger chunks
)
```

### Disable Table Preservation

```ruby
bridge = DoclingBridgeService.new
result = bridge.process_file(
  file_path,
  preserve_tables: false  # Extract as plain text
)
```

### Enable Image Extraction

```ruby
result = bridge.process_file(
  file_path,
  extract_images: true  # Include image metadata in chunks
)
```

## Best Practices

1. **Use Docling for complex documents** - PDFs with tables, multi-column layouts
2. **Use standard processing for simple files** - Plain text, simple markdown
3. **Set reasonable file size limits** - Prevent memory issues
4. **Monitor processing times** - Add timeouts for user experience
5. **Test fallback behavior** - Ensure system works without Docling

## Comparison: Docling vs Standard Processing

| Feature | Docling | Standard (PDF-reader) |
|---------|---------|----------------------|
| **Speed** | Slower (5-10s) | Faster (1-2s) |
| **Table extraction** | ✅ Markdown format | ❌ Plain text |
| **Multi-column PDFs** | ✅ Preserves flow | ⚠️ May scramble |
| **Headers/footers** | ✅ Detects & removes | ❌ Included as text |
| **Layout analysis** | ✅ Semantic structure | ❌ Linear text |
| **OCR support** | ✅ Built-in | ❌ Not available |
| **Office docs (DOCX)** | ✅ Native support | ❌ Not supported |
| **Memory usage** | Higher (300+ MB) | Lower (50-100 MB) |

## Future Enhancements

Potential improvements:
- [ ] Hybrid search (vector + keyword BM25)
- [ ] Image embedding for visual RAG
- [ ] Async processing for large files
- [ ] Document preprocessing pipeline
- [ ] Custom model fine-tuning

## Support

For issues or questions:
1. Check logs: `tail -f log/development.log | grep Docling`
2. Verify installation: `DoclingBridgeService.check_installation`
3. Test with sample document: `rails console` → process test file
4. Review Docling docs: https://github.com/DS4SD/docling

---

**Status**: ✅ Ready for testing
**Last Updated**: 2025-10-16
