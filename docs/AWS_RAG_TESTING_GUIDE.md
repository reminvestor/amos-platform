# AWS RAG System Testing Guide

**Last Updated:** November 2025
**Relates to:** AWS Bedrock Migration Phase 1

## Overview

This guide documents how to test the RAG (Retrieval-Augmented Generation) system after integrating AWS services including Textract OCR and Bedrock Knowledge Bases.

## System Architecture Changes

### Before AWS Integration
- **OCR**: Docling only
- **Storage**: pgvector + optional Pinecone
- **Processing**: Synchronous document processing

### After AWS Integration (Phase 1)
- **OCR**: Dual-mode (AWS Textract + Docling fallback)
- **Storage**: pgvector + optional Pinecone + Bedrock KB (Phase 2)
- **Processing**: Async for large documents, sync for small

## Test Environment Setup

### Required Environment Variables

```bash
# AWS Credentials
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key

# RAG Storage
RAG_BUCKET=agent-marketing-rag-storage

# OCR Configuration
OCR_PROVIDER=auto  # auto, textract, or docling
OCR_FALLBACK_ENABLED=true
OCR_DOCLING_MAX_SIZE_MB=5
OCR_TEXTRACT_PREFERRED_TYPES=invoice,receipt,id_document,passport

# Textract (optional)
TEXTRACT_SNS_TOPIC_ARN=arn:aws:sns:...
TEXTRACT_ROLE_ARN=arn:aws:iam::...
```

### Test Fixtures

Create test files in `test/fixtures/files/`:

```bash
test/fixtures/files/
├── sample.txt           # Plain text
├── test_doc.pdf         # Simple PDF
├── invoice.pdf          # Invoice for Textract
├── multipage.pdf        # Large multi-page PDF
└── brand_guidelines.pdf # Real-world document
```

## Testing Strategies

### 1. AWS Textract Service Tests

**Location**: `test/services/aws/textract_service_test.rb`

**Key Test Patterns:**

```ruby
# Mock setup for parallel test safety
setup do
  @entity = entities(:one)

  # Unique test file per process to avoid conflicts
  @test_file = Rails.root.join('tmp', "test_textract_#{Process.pid}_#{Random.rand(10000)}.pdf")
  FileUtils.mkdir_p(File.dirname(@test_file))
  File.write(@test_file, "PDF content placeholder")

  # Create mock clients
  @mock_textract_client = Minitest::Mock.new
  @mock_s3_client = Minitest::Mock.new

  # Initialize service with mocked clients
  @service = TextractService.instance
  @service.instance_variable_set(:@client, @mock_textract_client)
  @service.instance_variable_set(:@s3_client, @mock_s3_client)
end

# Define methods on mocks (NOT .expect pattern)
test "processes single page document" do
  def @mock_s3_client.put_object(params)
    OpenStruct.new(etag: 'test')
  end

  def @mock_textract_client.analyze_document(params)
    OpenStruct.new(
      blocks: [
        OpenStruct.new(block_type: 'PAGE', confidence: 0.99),
        OpenStruct.new(block_type: 'LINE', text: 'Test', confidence: 0.98)
      ],
      document_metadata: OpenStruct.new(pages: 1)
    )
  end

  result = @service.process_document(@entity, @test_file)

  assert result[:pages].present?
  assert_equal 1, result[:pages].count
end
```

**Important Testing Patterns:**

1. **Unique temp files**: Use `Process.pid` and random numbers for parallel test safety
2. **Method definition mocking**: Define methods directly on mock objects instead of `.expect`
3. **OpenStruct responses**: Match AWS SDK response structure exactly

**Tests to Run:**

```bash
# All Textract tests
rails test test/services/aws/textract_service_test.rb

# Specific test
rails test test/services/aws/textract_service_test.rb:150

# With parallelization
rails test test/services/aws/ --parallel=10
```

### 2. Bedrock Knowledge Base Service Tests

**Location**: `test/services/aws/bedrock_knowledge_base_service_test.rb`

**Key Considerations:**

- Bedrock KB manages documents internally via S3 sync
- No RagDocument records created (different from Docling pipeline)
- Test entity must have `bedrock_knowledge_base_id` set

**Example Test:**

```ruby
test "adds document to knowledge base" do
  file_path = Rails.root.join('test', 'fixtures', 'files', 'sample.txt')
  FileUtils.mkdir_p(File.dirname(file_path))
  File.write(file_path, "Test content")

  metadata = {
    category: 'test',
    source: 'unit_test'
  }

  # Mock S3 and Bedrock operations
  @service.s3_client.stub :put_object, OpenStruct.new(etag: 'test-etag') do
    @service.bedrock_agent_client.stub :list_data_sources,
      OpenStruct.new(data_source_summaries: [OpenStruct.new(data_source_id: 'ds-123')]) do
      @service.bedrock_agent_client.stub :start_ingestion_job,
        OpenStruct.new(ingestion_job: OpenStruct.new(ingestion_job_id: 'job-123', status: 'STARTING')) do

        result = @service.add_document(@entity, file_path, metadata)

        assert result[:success]
        assert result[:s3_key].present?
        assert result[:s3_key].starts_with?("documents/#{@entity.id}/")
      end
    end
  end

  FileUtils.rm_f(file_path)
end
```

**Common Pitfalls:**

1. ❌ **Don't** try to create RagDocument records in Bedrock KB tests
2. ❌ **Don't** use fields that don't exist (e.g., `bedrock_last_ingestion_at`)
3. ✅ **Do** verify S3 key format: `documents/{entity_id}/{filename}`
4. ✅ **Do** check ingestion job tracking on entity

### 3. Integration Tests: Dual-Mode OCR

**Location**: `test/integration/dual_mode_ocr_test.rb`

```ruby
test "uses Textract for invoices" do
  doc = upload_file('invoice.pdf', entity)

  assert_equal 'textract', doc.ocr_provider
  assert doc.textract_result.present?
  assert doc.textract_result[:expenses].present?
end

test "falls back to Docling on Textract failure" do
  # Simulate Textract failure
  TextractService.stub :process_document, ->(*args) { raise Aws::Textract::Errors::ServiceError.new('', '') } do
    doc = upload_file('test_doc.pdf', entity)

    assert_equal 'docling', doc.ocr_provider
    assert doc.docling_metadata.present?
  end
end

test "uses Docling for small documents (< 5MB)" do
  small_file = create_temp_pdf(size: 2.megabytes)
  doc = upload_file(small_file, entity)

  assert_equal 'docling', doc.ocr_provider
  # Should not incur Textract costs
end
```

### 4. Cost Tracking Tests

**Location**: `test/services/entity_cost_tracker_test.rb`

```ruby
test "tracks Textract usage costs" do
  assert_difference 'EntityUsageMetric.count', 1 do
    service = TextractService.instance
    service.process_document(entity, test_pdf)
  end

  metric = EntityUsageMetric.last
  assert_equal 'ocr', metric.category
  assert_equal 'textract', metric.service
  assert metric.estimated_cost_cents > 0
end

test "tracks Bedrock KB retrieval costs" do
  assert_difference 'EntityUsageMetric.count', 1 do
    service = BedrockKnowledgeBaseService.instance
    service.query(entity, "test query")
  end

  metric = EntityUsageMetric.last
  assert_equal 'search', metric.category
  assert_equal 'bedrock_kb_retrieval', metric.service
end
```

## Test Execution Commands

### Run All AWS Tests

```bash
# All AWS service tests
docker compose exec web bundle exec rails test test/services/aws/

# Specific service
docker compose exec web bundle exec rails test test/services/aws/textract_service_test.rb
docker compose exec web bundle exec rails test test/services/aws/bedrock_knowledge_base_service_test.rb
docker compose exec web bundle exec rails test test/services/aws/comprehend_service_test.rb

# With parallelization (faster)
docker compose exec web bundle exec rails test test/services/aws/ --parallel=10
```

### Run Integration Tests

```bash
# Dual-mode OCR integration
docker compose exec web bundle exec rails test test/integration/dual_mode_ocr_test.rb

# Cost tracking
docker compose exec web bundle exec rails test test/services/entity_cost_tracker_test.rb
```

### Run Full Test Suite

```bash
# All tests (1362 tests)
docker compose exec web bundle exec rails test

# Faster with parallelization
docker compose exec web bundle exec rails test --parallel=10
```

## Debugging Failing Tests

### Common Issues and Fixes

#### 1. File Not Found Errors (Parallel Tests)

**Problem:**
```
ArgumentError: File not found: /rails/tmp/test_textract.pdf
```

**Cause:** Multiple tests sharing the same temp file path

**Fix:** Use unique filenames per test process
```ruby
@test_file = Rails.root.join('tmp', "test_textract_#{Process.pid}_#{Random.rand(10000)}.pdf")
```

#### 2. Mock Expectation Failures

**Problem:**
```
ArgumentError: mocked method :put_object expects 1 arguments, got []
```

**Cause:** Using `.expect` pattern with Minitest::Mock

**Fix:** Define methods directly on mock objects
```ruby
# ❌ Don't do this:
@mock_s3_client.expect :put_object, response, [Hash]

# ✅ Do this instead:
def @mock_s3_client.put_object(params)
  OpenStruct.new(etag: 'test-etag')
end
```

#### 3. Unknown Attribute Errors

**Problem:**
```
ActiveModel::UnknownAttributeError: unknown attribute 'file_size' for RagDocument
```

**Cause:** Using field names that don't exist in schema

**Fix:** Check actual schema:
```bash
docker compose exec web rails runner "puts RagDocument.column_names.join(', ')"
```

Use correct field names:
- `original_filename` (not `file_name`)
- `file_size_bytes` (not `file_size`)
- No `file_path` field (use metadata)

#### 4. Missing Required Fields

**Problem:**
```
ActiveRecord::RecordInvalid: Validation failed: Rag store can't be blank
```

**Cause:** RagDocument requires `belongs_to :rag_store`

**Fix:** For Bedrock KB, don't create RagDocument records. Bedrock manages documents internally.

## Manual Testing Procedures

### 1. Test Document Upload Flow

```bash
# Start Rails console
docker compose exec web rails console

# Upload a test document
entity = Entity.first
file_path = Rails.root.join('test', 'fixtures', 'files', 'test_doc.pdf')

# Via Docling (traditional path)
doc = Rag::DocumentPipelineJob.perform_now(
  rag_store_id: entity.rag_stores.first.id,
  file_path: file_path
)

# Via Textract (new path)
textract = Aws::TextractService.instance
result = textract.process_document(entity, file_path)
puts result.inspect
```

### 2. Test Bedrock KB Integration

```bash
# Rails console
entity = Entity.first

# Create KB if needed
kb_service = Aws::BedrockKnowledgeBaseService.instance
kb = kb_service.create_knowledge_base(entity)

# Add document
file_path = 'path/to/doc.pdf'
result = kb_service.add_document(entity, file_path, { category: 'test' })
puts result.inspect

# Query
query_result = kb_service.query(entity, "What is the company policy?")
puts query_result[:results].first[:content]
```

### 3. Test OCR Provider Selection

```ruby
# Small document → Docling
small_pdf = create_file(size: 2.megabytes)
service = Ocr::DualModeService.new
provider = service.send(:select_provider, small_pdf, {})
assert_equal :docling, provider

# Invoice → Textract
invoice_pdf = 'invoice.pdf'
provider = service.send(:select_provider, invoice_pdf, { document_type: 'invoice' })
assert_equal :textract, provider
```

## Performance Testing

### Measure OCR Processing Time

```ruby
require 'benchmark'

file_path = 'large_document.pdf'
entity = Entity.first

# Textract
textract_time = Benchmark.realtime do
  Aws::TextractService.instance.process_document(entity, file_path)
end

# Docling
docling_time = Benchmark.realtime do
  DoclingOcrService.new.process_document(file_path)
end

puts "Textract: #{textract_time.round(2)}s"
puts "Docling: #{docling_time.round(2)}s"
puts "Speedup: #{(docling_time / textract_time).round(1)}x"
```

### Cost Comparison

```ruby
# Get cost metrics
entity = Entity.first
start_date = 1.month.ago

textract_costs = EntityUsageMetric
  .where(entity: entity, service: 'textract')
  .where('created_at >= ?', start_date)
  .sum(:estimated_cost_cents) / 100.0

docling_costs = 0 # Docling is free (self-hosted)

puts "Textract: $#{textract_costs}"
puts "Docling: $#{docling_costs}"
puts "Total: $#{textract_costs}"
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Test AWS RAG System

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: pgvector/pgvector:pg16
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    env:
      AWS_REGION: us-east-1
      AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
      AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      RAG_BUCKET: ${{ secrets.RAG_BUCKET }}
      OCR_PROVIDER: auto
      OCR_FALLBACK_ENABLED: true

    steps:
      - uses: actions/checkout@v3

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.3.0
          bundler-cache: true

      - name: Setup Database
        run: |
          bundle exec rails db:create
          bundle exec rails db:migrate

      - name: Run AWS Tests
        run: bundle exec rails test test/services/aws/

      - name: Run Integration Tests
        run: bundle exec rails test test/integration/
```

## Test Coverage Goals

### Current Coverage (Post Phase 1)

- ✅ **Textract Service**: 26 tests, 62 assertions, 100% passing
- ✅ **Bedrock KB Service**: 13 tests, 37 assertions, 100% passing
- ✅ **Dual-Mode OCR**: Integration tests for provider selection
- ✅ **Cost Tracking**: Metrics for all AWS services

### Phase 2 Coverage (Bedrock KB Activation)

- ⏳ Bedrock KB query performance tests
- ⏳ Hybrid search (Bedrock + pgvector) tests
- ⏳ Document sync integrity tests
- ⏳ Ingestion job monitoring tests

### Phase 3 Coverage (Comprehend Integration)

- ⏳ Entity extraction accuracy tests
- ⏳ Key phrase detection tests
- ⏳ Sentiment analysis tests
- ⏳ PII detection tests

## Best Practices

### 1. Test Isolation

- **Always** use unique temp files in parallel tests
- **Never** share state between tests
- **Clean up** temp files in teardown

### 2. Mock Patterns

- **Use** direct method definitions on mocks
- **Avoid** `.expect` pattern with AWS SDK mocks
- **Match** AWS SDK response structure exactly with OpenStruct

### 3. Test Data

- **Keep** test fixtures small (< 1MB)
- **Use** representative real-world documents
- **Version control** test fixtures

### 4. Cost Awareness

- **Mock** AWS calls in unit tests (avoid real API costs)
- **Use** development tier for integration tests
- **Monitor** test execution costs in CI/CD

### 5. Debugging

- **Enable** detailed logging: `Rails.logger.level = :debug`
- **Check** rescue blocks for swallowed errors
- **Verify** environment variables are set
- **Use** `rails runner` for quick script tests

## Troubleshooting

### Tests Pass Locally But Fail in CI

1. **Check environment variables**: Ensure AWS credentials are set in CI secrets
2. **Verify service availability**: Test AWS endpoints from CI environment
3. **Check parallelization**: Some tests may not be parallel-safe
4. **Database state**: Ensure fixtures load correctly

### Slow Test Execution

1. **Use parallelization**: `--parallel=10` flag
2. **Mock external services**: Don't make real AWS calls in unit tests
3. **Optimize fixtures**: Use minimal test data
4. **Database cleanup**: Use transactional fixtures

### Intermittent Failures

1. **Race conditions**: Check for shared temp files
2. **Network timeouts**: Increase timeout values for AWS calls
3. **Mock setup**: Ensure mocks are properly reset between tests

## Resources

- [AWS Textract Documentation](https://docs.aws.amazon.com/textract/)
- [AWS Bedrock Knowledge Bases](https://docs.aws.amazon.com/bedrock/latest/userguide/knowledge-base.html)
- [Minitest Documentation](https://github.com/minitest/minitest)
- [Rails Testing Guide](https://guides.rubyonrails.org/testing.html)

## Next Steps

After AWS migration Phase 1 is complete and all tests pass:

1. **Phase 2**: Activate Bedrock Knowledge Bases
   - Test hybrid search (Bedrock + pgvector)
   - Measure query performance vs current system
   - Test document sync accuracy

2. **Phase 3**: Integrate Comprehend NLP
   - Test entity extraction
   - Test PII detection
   - Measure processing overhead

3. **Phase 4**: Advanced Features
   - Multi-modal search tests
   - Cross-document relationship tests
   - Real-time ingestion tests

---

**Document Version**: 1.0
**Last Test Run**: November 2025
**Test Suite Status**: ✅ All AWS tests passing (58/58)
