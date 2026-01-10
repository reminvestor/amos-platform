# AWS Bedrock & Services Migration Plan

## Executive Summary

This plan outlines the migration of our RAG and OCR systems to AWS-native services, leveraging AWS Bedrock Knowledge Bases, Amazon Textract, and other AWS services for improved scalability, reliability, and cost-effectiveness.

## Current State Analysis

### Existing RAG Implementation
- **Vector Storage**: PostgreSQL with pgvector extension + Pinecone (optional)
- **Embeddings**: AWS Bedrock Titan (amazon.titan-embed-text-v1)
- **Document Processing**: Docling (Python library)
- **Search**: Hybrid (vector + keyword) search
- **Storage**: S3 for raw documents
- **Caching**: Redis for query caching

### Existing OCR Implementation
- **OCR Engine**: Docling with EasyOCR backend
- **Document Types**: PDF, images, tables
- **Chunking**: Simple (paragraph-based) and semantic (token-aware)
- **Processing**: Python script invoked from Ruby

## Target Architecture

### AWS Services to Implement

1. **AWS Bedrock Knowledge Bases** (Primary RAG)
   - Fully managed RAG solution
   - Built-in vector database (Amazon OpenSearch Serverless)
   - Automatic chunking and embedding
   - Native Bedrock integration

2. **Amazon Textract** (OCR/Document Processing)
   - Serverless OCR service
   - Advanced table and form extraction
   - Multi-page PDF support
   - Handwriting recognition

3. **Amazon Kendra** (Enterprise Search - Optional)
   - Enterprise-grade semantic search
   - Natural language processing
   - Document ranking and relevance
   - Built-in connectors

4. **Amazon Comprehend** (NLP Enhancement)
   - Entity recognition
   - Sentiment analysis
   - Key phrase extraction
   - Topic modeling

5. **AWS Lambda** (Processing Pipeline)
   - Document processing workflows
   - Async chunking operations
   - API orchestration

6. **Amazon SQS/SNS** (Event Processing)
   - Document processing queue
   - Event notifications
   - Workflow orchestration

7. **Amazon OpenSearch** (Advanced Search)
   - Vector search capabilities
   - Full-text search
   - Analytics and aggregations

8. **AWS Step Functions** (Workflow Orchestration)
   - Complex document processing workflows
   - Error handling and retries
   - State management

## Migration Phases

### Phase 1: OCR Migration to Amazon Textract (Week 1-2)

**Objective**: Replace Docling OCR with Amazon Textract

#### Implementation Steps:

1. **Create Textract Service Class**
```ruby
# app/services/aws/textract_service.rb
class Aws::TextractService
  def initialize(entity)
    @entity = entity
    @client = Aws::Textract::Client.new(region: ENV['AWS_REGION'])
    @s3_service = Aws::S3Service.new(entity)
  end

  def process_document(file_path, options = {})
    # Upload to S3
    s3_object = @s3_service.upload_temp_file(file_path)

    # Start async document analysis
    job_id = start_document_analysis(s3_object, options)

    # Queue job for processing
    TextractProcessingJob.perform_later(@entity.id, job_id, s3_object.key)

    { job_id: job_id, status: 'processing' }
  end

  def extract_text(s3_key)
    response = @client.detect_document_text(
      document: { s3_object: { bucket: bucket_name, name: s3_key } }
    )
    parse_text_response(response)
  end

  def extract_tables(s3_key)
    response = @client.analyze_document(
      document: { s3_object: { bucket: bucket_name, name: s3_key } },
      feature_types: ['TABLES', 'FORMS']
    )
    parse_table_response(response)
  end
end
```

2. **Update Document Processing Pipeline**
```ruby
# app/services/document_processor_service.rb
class DocumentProcessorService
  def process(document)
    case processing_engine
    when 'textract'
      textract_service.process_document(document.file_path)
    when 'docling'
      docling_service.process_document(document.file_path) # Fallback
    end
  end
end
```

3. **Create Textract Background Jobs**
```ruby
# app/jobs/textract_processing_job.rb
class TextractProcessingJob < ApplicationJob
  def perform(entity_id, job_id, s3_key)
    entity = Entity.find(entity_id)
    service = Aws::TextractService.new(entity)

    # Check job status
    result = service.get_job_result(job_id)

    if result[:status] == 'SUCCEEDED'
      # Extract and store text
      chunks = service.parse_document_result(result)
      store_chunks(entity, chunks, s3_key)
    elsif result[:status] == 'IN_PROGRESS'
      # Re-queue for later
      TextractProcessingJob.set(wait: 30.seconds).perform_later(entity_id, job_id, s3_key)
    end
  end
end
```

### Phase 2: RAG Migration to Bedrock Knowledge Bases (Week 2-4)

**Objective**: Implement AWS Bedrock Knowledge Bases for RAG

#### Implementation Steps:

1. **Create Bedrock Knowledge Base**
```ruby
# app/services/aws/bedrock_knowledge_base_service.rb
class Aws::BedrockKnowledgeBaseService
  def initialize(entity)
    @entity = entity
    @client = Aws::BedrockAgent::Client.new(region: ENV['AWS_REGION'])
    @runtime_client = Aws::BedrockAgentRuntime::Client.new(region: ENV['AWS_REGION'])
  end

  def create_knowledge_base
    response = @client.create_knowledge_base(
      name: "entity-#{@entity.id}-kb",
      description: "Knowledge base for #{@entity.name}",
      role_arn: ENV['BEDROCK_KB_ROLE_ARN'],
      knowledge_base_configuration: {
        type: 'VECTOR',
        vector_knowledge_base_configuration: {
          embedding_model_arn: embedding_model_arn
        }
      },
      storage_configuration: {
        type: 'OPENSEARCH_SERVERLESS',
        opensearch_serverless_configuration: {
          collection_arn: collection_arn,
          vector_index_name: "entity-#{@entity.id}-index",
          field_mapping: {
            vector_field: 'embedding',
            text_field: 'content',
            metadata_field: 'metadata'
          }
        }
      }
    )

    @entity.update!(bedrock_kb_id: response.knowledge_base.knowledge_base_id)
  end

  def add_document(document_path, metadata = {})
    # Create data source
    data_source = create_s3_data_source(document_path, metadata)

    # Start ingestion job
    @client.start_ingestion_job(
      knowledge_base_id: @entity.bedrock_kb_id,
      data_source_id: data_source.data_source_id
    )
  end

  def query(user_query, options = {})
    response = @runtime_client.retrieve_and_generate(
      input: { text: user_query },
      retrieve_and_generate_configuration: {
        type: 'KNOWLEDGE_BASE',
        knowledge_base_configuration: {
          knowledge_base_id: @entity.bedrock_kb_id,
          model_arn: model_arn,
          retrieval_configuration: {
            vector_search_configuration: {
              number_of_results: options[:top_k] || 10
            }
          }
        }
      }
    )

    parse_rag_response(response)
  end
end
```

2. **Update RAG Service to Support Dual Mode**
```ruby
# app/services/rag_service.rb
class RagService
  def initialize(entity)
    @entity = entity
    @mode = determine_rag_mode(entity)

    case @mode
    when :bedrock_kb
      @backend = Aws::BedrockKnowledgeBaseService.new(entity)
    when :hybrid
      @backend = HybridRagQueryService.new(entity)
    end
  end

  def search(query, options = {})
    @backend.query(query, options)
  end

  private

  def determine_rag_mode(entity)
    # Gradual rollout: Use feature flag or entity setting
    if entity.use_bedrock_kb? || ENV['USE_BEDROCK_KB'] == 'true'
      :bedrock_kb
    else
      :hybrid
    end
  end
end
```

### Phase 3: Advanced Features Integration (Week 4-6)

#### 3.1 Amazon Comprehend Integration
```ruby
# app/services/aws/comprehend_service.rb
class Aws::ComprehendService
  def initialize
    @client = Aws::Comprehend::Client.new(region: ENV['AWS_REGION'])
  end

  def analyze_document(text)
    # Entity detection
    entities = @client.detect_entities(text: text, language_code: 'en')

    # Key phrases
    key_phrases = @client.detect_key_phrases(text: text, language_code: 'en')

    # Sentiment
    sentiment = @client.detect_sentiment(text: text, language_code: 'en')

    # Topics (for longer documents)
    topics = detect_topics(text) if text.length > 5000

    {
      entities: parse_entities(entities),
      key_phrases: parse_key_phrases(key_phrases),
      sentiment: sentiment.sentiment,
      topics: topics
    }
  end

  def enhance_metadata(document)
    analysis = analyze_document(document.content)

    document.update!(
      metadata: document.metadata.merge(
        entities: analysis[:entities],
        key_phrases: analysis[:key_phrases],
        sentiment: analysis[:sentiment],
        topics: analysis[:topics],
        comprehend_analyzed_at: Time.current
      )
    )
  end
end
```

#### 3.2 Step Functions Workflow
```ruby
# app/services/aws/step_functions_service.rb
class Aws::StepFunctionsService
  def initialize
    @client = Aws::States::Client.new(region: ENV['AWS_REGION'])
  end

  def start_document_workflow(document_id)
    @client.start_execution(
      state_machine_arn: ENV['DOCUMENT_WORKFLOW_ARN'],
      name: "doc-process-#{document_id}-#{Time.now.to_i}",
      input: {
        document_id: document_id,
        steps: [
          'textract_ocr',
          'comprehend_analysis',
          'bedrock_embedding',
          'knowledge_base_ingestion',
          'notification'
        ]
      }.to_json
    )
  end
end
```

### Phase 4: Infrastructure as Code (Week 6-7)

#### Terraform Configuration

```hcl
# aws/terraform/bedrock-rag.tf

# Bedrock Knowledge Base
resource "aws_bedrockagent_knowledge_base" "main" {
  name        = "${var.app_name}-knowledge-base"
  description = "Main knowledge base for RAG system"
  role_arn    = aws_iam_role.bedrock_kb.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = data.aws_bedrock_foundation_model.titan_embed.arn
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn     = aws_opensearchserverless_collection.rag.arn
      vector_index_name  = "rag-index"
      field_mapping {
        vector_field   = "embedding"
        text_field     = "content"
        metadata_field = "metadata"
      }
    }
  }
}

# OpenSearch Serverless Collection
resource "aws_opensearchserverless_collection" "rag" {
  name = "${var.app_name}-rag-collection"
  type = "VECTORSEARCH"
}

# Step Functions State Machine
resource "aws_sfn_state_machine" "document_workflow" {
  name     = "${var.app_name}-document-workflow"
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "Document processing workflow"
    StartAt = "ProcessWithTextract"
    States = {
      ProcessWithTextract = {
        Type     = "Task"
        Resource = aws_lambda_function.textract_processor.arn
        Next     = "AnalyzeWithComprehend"
      }
      AnalyzeWithComprehend = {
        Type     = "Task"
        Resource = aws_lambda_function.comprehend_analyzer.arn
        Next     = "GenerateEmbeddings"
      }
      GenerateEmbeddings = {
        Type     = "Task"
        Resource = aws_lambda_function.embedding_generator.arn
        Next     = "IngestToKnowledgeBase"
      }
      IngestToKnowledgeBase = {
        Type     = "Task"
        Resource = aws_lambda_function.kb_ingestor.arn
        End      = true
      }
    }
  })
}
```

## Implementation Timeline

| Phase | Duration | Start Date | End Date | Dependencies |
|-------|----------|------------|----------|--------------|
| Phase 1: OCR Migration | 2 weeks | Week 1 | Week 2 | AWS Textract access |
| Phase 2: Bedrock KB Setup | 2 weeks | Week 2 | Week 4 | Phase 1 completion |
| Phase 3: Advanced Features | 2 weeks | Week 4 | Week 6 | Phase 2 completion |
| Phase 4: Infrastructure | 1 week | Week 6 | Week 7 | All phases |
| Testing & Optimization | 1 week | Week 7 | Week 8 | Phase 4 completion |

## Cost Analysis

### Current Costs (Monthly Estimate)
- Docling Processing: ~$500 (compute costs)
- pgvector Storage: ~$200 (RDS costs)
- Pinecone (if used): ~$750
- Total: ~$1,450/month

### Projected AWS Costs (Monthly Estimate)
- Textract: ~$300 (10K pages @ $0.03/page)
- Bedrock Knowledge Base: ~$400
- OpenSearch Serverless: ~$350
- Comprehend: ~$200
- Step Functions: ~$50
- Lambda: ~$100
- Total: ~$1,400/month

**Savings**: Approximately same cost with significantly improved capabilities

## Benefits

1. **Scalability**
   - Serverless architecture scales automatically
   - No infrastructure management
   - Handle millions of documents

2. **Performance**
   - Native AWS integration reduces latency
   - Optimized vector search with OpenSearch
   - Parallel processing with Step Functions

3. **Reliability**
   - AWS managed services with high availability
   - Built-in error handling and retries
   - Automatic backups and disaster recovery

4. **Features**
   - Advanced OCR with Textract
   - NLP enhancement with Comprehend
   - Unified search with Bedrock KB
   - Real-time document processing

5. **Cost Optimization**
   - Pay-per-use pricing
   - No idle resources
   - Automatic scaling

## Migration Rollback Plan

### Dual-Mode Operation
- Keep existing system running in parallel
- Use feature flags for gradual rollout
- A/B testing between old and new systems

### Rollback Triggers
- Error rate > 5%
- Latency > 2x current system
- Cost overrun > 20%

### Rollback Procedure
1. Disable feature flag for new system
2. Route traffic back to old system
3. Investigate and fix issues
4. Retry migration with fixes

## Monitoring & Observability

### Key Metrics
- Document processing time
- Query response time
- Embedding generation rate
- Knowledge base ingestion success rate
- OCR accuracy
- Cost per document

### Dashboards
```ruby
# app/services/monitoring/rag_metrics.rb
class Monitoring::RagMetrics
  def track_document_processing(document_id, duration, service)
    CloudWatch.put_metric_data(
      namespace: 'AMOS/RAG',
      metric_data: [
        {
          metric_name: 'DocumentProcessingTime',
          dimensions: [
            { name: 'Service', value: service },
            { name: 'EntityId', value: entity_id }
          ],
          value: duration,
          unit: 'Seconds'
        }
      ]
    )
  end
end
```

## Security Considerations

1. **Data Encryption**
   - Encryption at rest for all services
   - TLS for data in transit
   - KMS key management

2. **Access Control**
   - IAM roles for service authentication
   - Resource-based policies
   - VPC endpoints for private connectivity

3. **Compliance**
   - HIPAA eligible services
   - SOC 2 compliance
   - Data residency controls

## Testing Strategy

### Unit Tests
```ruby
# test/services/aws/textract_service_test.rb
class Aws::TextractServiceTest < ActiveSupport::TestCase
  test "processes PDF document" do
    VCR.use_cassette("textract_pdf") do
      service = Aws::TextractService.new(entities(:acme))
      result = service.process_document("test.pdf")

      assert_equal 'processing', result[:status]
      assert_not_nil result[:job_id]
    end
  end
end
```

### Integration Tests
```ruby
# test/integration/bedrock_kb_integration_test.rb
class BedrockKbIntegrationTest < ActionDispatch::IntegrationTest
  test "end-to-end document processing" do
    document = create_test_document

    # Upload and process
    post api_documents_path, params: { file: document }
    assert_response :success

    # Wait for processing
    wait_for_processing(response.parsed_body['id'])

    # Query knowledge base
    get api_search_path, params: { q: "test query" }
    assert_response :success
    assert_not_empty response.parsed_body['results']
  end
end
```

## Success Criteria

1. **Performance**
   - Query response time < 500ms (p95)
   - Document processing < 2 min for 100 pages
   - 99.9% availability

2. **Quality**
   - OCR accuracy > 95%
   - Relevant search results in top 3
   - Zero data loss during migration

3. **Cost**
   - Monthly costs within 10% of projection
   - Cost per document < $0.05
   - ROI positive within 3 months

## Next Steps

1. **Immediate Actions**
   - [ ] Request AWS service quota increases
   - [ ] Set up development AWS accounts
   - [ ] Create IAM roles and policies
   - [ ] Initialize Terraform workspace

2. **Week 1 Tasks**
   - [ ] Implement Textract service class
   - [ ] Create S3 upload pipeline
   - [ ] Set up CloudWatch monitoring
   - [ ] Begin unit test coverage

3. **Stakeholder Communication**
   - [ ] Present plan to engineering team
   - [ ] Get security team approval
   - [ ] Schedule weekly progress reviews
   - [ ] Create user communication plan

## Appendix

### A. AWS Service Limits

| Service | Default Limit | Required | Action |
|---------|--------------|----------|--------|
| Textract | 10 TPS | 50 TPS | Request increase |
| Bedrock KB | 5 per account | 10 | Request increase |
| OpenSearch | 10 collections | 20 | Request increase |
| Lambda | 1000 concurrent | 2000 | Request increase |

### B. Environment Variables

```bash
# .env.example additions
AWS_REGION=us-east-1
BEDROCK_KB_ENABLED=true
TEXTRACT_ENABLED=true
COMPREHEND_ENABLED=true
OPENSEARCH_ENDPOINT=https://xxx.us-east-1.aoss.amazonaws.com
BEDROCK_KB_ID=kb-xxxxx
BEDROCK_KB_ROLE_ARN=arn:aws:iam::xxx:role/bedrock-kb-role
DOCUMENT_WORKFLOW_ARN=arn:aws:states:us-east-1:xxx:stateMachine:document-workflow
```

### C. Database Migrations

```ruby
# db/migrate/add_aws_fields_to_entities.rb
class AddAwsFieldsToEntities < ActiveRecord::Migration[7.1]
  def change
    add_column :entities, :bedrock_kb_id, :string
    add_column :entities, :opensearch_collection_arn, :string
    add_column :entities, :use_bedrock_kb, :boolean, default: false
    add_index :entities, :bedrock_kb_id
  end
end

# db/migrate/add_textract_fields_to_documents.rb
class AddTextractFieldsToDocuments < ActiveRecord::Migration[7.1]
  def change
    add_column :rag_documents, :textract_job_id, :string
    add_column :rag_documents, :textract_status, :string
    add_column :rag_documents, :textract_result, :jsonb
    add_column :rag_documents, :comprehend_analysis, :jsonb
    add_index :rag_documents, :textract_job_id
  end
end
```

## Conclusion

This migration plan provides a comprehensive roadmap to modernize our RAG and OCR systems using AWS native services. The phased approach ensures minimal disruption while delivering improved capabilities, better scalability, and enhanced reliability. The dual-mode operation and rollback plan provide safety nets during the transition.

Key advantages of this migration:
- **Unified Platform**: All services under AWS ecosystem
- **Serverless Architecture**: No infrastructure management
- **Advanced Capabilities**: Superior OCR, NLP, and search features
- **Cost Neutral**: Similar costs with significantly more features
- **Future Ready**: Easy to add new AWS AI services as they become available

The migration aligns with our strategic goal of leveraging AWS as our primary cloud platform and positions us for future growth and innovation in AI-powered document processing and knowledge management.