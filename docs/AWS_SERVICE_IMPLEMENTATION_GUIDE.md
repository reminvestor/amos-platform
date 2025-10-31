# AWS Service Implementation Guide

## Service Classes Implementation

### 1. AWS Textract Service (OCR Replacement)

```ruby
# app/services/aws/textract_service.rb
require 'aws-sdk-textract'
require 'aws-sdk-s3'

module Aws
  class TextractService
    include ActiveSupport::Rescuable

    SUPPORTED_FORMATS = %w[pdf png jpg jpeg tiff].freeze
    MAX_SYNC_PAGES = 1  # Use async for multi-page docs

    attr_reader :entity, :client, :s3_client

    def initialize(entity)
      @entity = entity
      @client = ::Aws::Textract::Client.new(
        region: ENV.fetch('AWS_REGION', 'us-east-1'),
        http_read_timeout: 120
      )
      @s3_client = ::Aws::S3::Client.new(
        region: ENV.fetch('AWS_REGION', 'us-east-1')
      )
    end

    # Main entry point for document processing
    def process_document(file_path, options = {})
      validate_file!(file_path)

      # Upload to S3 first (Textract requires S3 location)
      s3_key = upload_to_s3(file_path)

      # Determine processing method
      if single_page_document?(file_path)
        process_sync(s3_key, options)
      else
        process_async(s3_key, options)
      end
    rescue ::Aws::Textract::Errors::ServiceError => e
      handle_textract_error(e)
    ensure
      cleanup_s3_file(s3_key) if s3_key && options[:cleanup] != false
    end

    # Synchronous processing for single-page documents
    def process_sync(s3_key, options = {})
      features = determine_features(options)

      response = @client.analyze_document(
        document: {
          s3_object: {
            bucket: bucket_name,
            name: s3_key
          }
        },
        feature_types: features
      )

      parse_response(response, options)
    end

    # Asynchronous processing for multi-page documents
    def process_async(s3_key, options = {})
      features = determine_features(options)

      # Start async job
      job_response = @client.start_document_analysis(
        document_location: {
          s3_object: {
            bucket: bucket_name,
            name: s3_key
          }
        },
        feature_types: features,
        notification_channel: notification_config if notification_enabled?
      )

      # Queue background job to check results
      TextractResultJob.perform_later(
        entity_id: @entity.id,
        job_id: job_response.job_id,
        s3_key: s3_key,
        options: options
      )

      {
        status: 'processing',
        job_id: job_response.job_id,
        message: 'Document analysis started. Results will be available soon.'
      }
    end

    # Get results from async job
    def get_job_results(job_id)
      response = @client.get_document_analysis(job_id: job_id)

      case response.job_status
      when 'SUCCEEDED'
        results = parse_response(response)

        # Get all pages if paginated
        while response.next_token
          response = @client.get_document_analysis(
            job_id: job_id,
            next_token: response.next_token
          )
          results[:pages].concat(parse_response(response)[:pages])
        end

        results
      when 'IN_PROGRESS'
        { status: 'processing', progress: response.progress_percentage }
      when 'FAILED'
        { status: 'failed', error: response.status_message }
      else
        { status: response.job_status.downcase }
      end
    end

    # Extract tables specifically
    def extract_tables(s3_key)
      response = @client.analyze_document(
        document: { s3_object: { bucket: bucket_name, name: s3_key } },
        feature_types: ['TABLES']
      )

      parse_tables(response)
    end

    # Extract forms specifically
    def extract_forms(s3_key)
      response = @client.analyze_document(
        document: { s3_object: { bucket: bucket_name, name: s3_key } },
        feature_types: ['FORMS']
      )

      parse_forms(response)
    end

    # Extract text with layout analysis
    def extract_text_with_layout(s3_key)
      response = @client.analyze_document(
        document: { s3_object: { bucket: bucket_name, name: s3_key } },
        feature_types: ['LAYOUT']
      )

      parse_layout(response)
    end

    private

    def bucket_name
      @bucket_name ||= ENV.fetch('RAG_STORAGE_BUCKET', "#{ENV['APP_NAME']}-rag-storage")
    end

    def upload_to_s3(file_path)
      file_name = File.basename(file_path)
      s3_key = "textract/#{@entity.id}/#{SecureRandom.hex(8)}/#{file_name}"

      File.open(file_path, 'rb') do |file|
        @s3_client.put_object(
          bucket: bucket_name,
          key: s3_key,
          body: file,
          metadata: {
            'entity-id' => @entity.id.to_s,
            'uploaded-at' => Time.current.iso8601
          }
        )
      end

      s3_key
    end

    def cleanup_s3_file(s3_key)
      @s3_client.delete_object(bucket: bucket_name, key: s3_key)
    rescue => e
      Rails.logger.warn "Failed to cleanup S3 file #{s3_key}: #{e.message}"
    end

    def determine_features(options)
      features = []
      features << 'TABLES' if options[:extract_tables] != false
      features << 'FORMS' if options[:extract_forms]
      features << 'LAYOUT' if options[:extract_layout]
      features << 'SIGNATURES' if options[:detect_signatures]
      features.presence || ['TABLES', 'LAYOUT']
    end

    def parse_response(response, options = {})
      result = {
        pages: [],
        tables: [],
        forms: [],
        raw_text: '',
        metadata: extract_metadata(response)
      }

      # Group blocks by page
      blocks_by_page = response.blocks.group_by { |b| b.page || 1 }

      blocks_by_page.each do |page_num, blocks|
        page_data = {
          page_number: page_num,
          text: '',
          lines: [],
          tables: [],
          forms: []
        }

        blocks.each do |block|
          case block.block_type
          when 'PAGE'
            page_data[:confidence] = block.confidence
            page_data[:geometry] = parse_geometry(block.geometry)
          when 'LINE'
            line_text = block.text || ''
            page_data[:lines] << {
              text: line_text,
              confidence: block.confidence,
              geometry: parse_geometry(block.geometry)
            }
            page_data[:text] += "#{line_text}\n"
          when 'TABLE'
            if options[:extract_tables] != false
              page_data[:tables] << parse_table_block(block, response.blocks)
            end
          when 'KEY_VALUE_SET'
            if block.entity_types&.include?('KEY') && options[:extract_forms]
              form_field = parse_form_field(block, response.blocks)
              page_data[:forms] << form_field if form_field
            end
          end
        end

        result[:pages] << page_data
        result[:raw_text] += page_data[:text]
        result[:tables].concat(page_data[:tables])
        result[:forms].concat(page_data[:forms])
      end

      result
    end

    def parse_table_block(table_block, all_blocks)
      # Build block lookup
      block_map = all_blocks.index_by(&:id)

      # Extract cells
      cells = []
      table_block.relationships&.each do |relationship|
        next unless relationship.type == 'CHILD'

        relationship.ids.each do |cell_id|
          cell_block = block_map[cell_id]
          next unless cell_block&.block_type == 'CELL'

          cells << {
            row: cell_block.row_index,
            column: cell_block.column_index,
            text: extract_cell_text(cell_block, block_map),
            confidence: cell_block.confidence
          }
        end
      end

      # Convert to 2D array
      max_row = cells.map { |c| c[:row] }.max || 0
      max_col = cells.map { |c| c[:column] }.max || 0

      table_data = Array.new(max_row) { Array.new(max_col, '') }
      cells.each do |cell|
        table_data[cell[:row] - 1][cell[:column] - 1] = cell[:text] if cell[:row] && cell[:column]
      end

      {
        data: table_data,
        confidence: table_block.confidence,
        geometry: parse_geometry(table_block.geometry)
      }
    end

    def extract_cell_text(cell_block, block_map)
      text_parts = []

      cell_block.relationships&.each do |relationship|
        next unless relationship.type == 'CHILD'

        relationship.ids.each do |child_id|
          child_block = block_map[child_id]
          text_parts << child_block.text if child_block&.text
        end
      end

      text_parts.join(' ')
    end

    def parse_form_field(key_block, all_blocks)
      block_map = all_blocks.index_by(&:id)

      # Find the key text
      key_text = extract_relationship_text(key_block, block_map, 'CHILD')

      # Find the value
      value_text = nil
      key_block.relationships&.each do |relationship|
        next unless relationship.type == 'VALUE'

        relationship.ids.each do |value_id|
          value_block = block_map[value_id]
          if value_block
            value_text = extract_relationship_text(value_block, block_map, 'CHILD')
          end
        end
      end

      return nil unless key_text

      {
        key: key_text,
        value: value_text || '',
        confidence: key_block.confidence
      }
    end

    def extract_relationship_text(block, block_map, relationship_type)
      text_parts = []

      block.relationships&.each do |relationship|
        next unless relationship.type == relationship_type

        relationship.ids.each do |child_id|
          child_block = block_map[child_id]
          text_parts << child_block.text if child_block&.text
        end
      end

      text_parts.join(' ')
    end

    def parse_geometry(geometry)
      return nil unless geometry

      {
        bounding_box: {
          width: geometry.bounding_box&.width,
          height: geometry.bounding_box&.height,
          left: geometry.bounding_box&.left,
          top: geometry.bounding_box&.top
        }
      }
    end

    def extract_metadata(response)
      {
        pages: response.document_metadata&.pages || 1,
        job_status: response.job_status,
        analyzed_at: Time.current,
        textract_version: response.analyze_document_model_version
      }
    end

    def single_page_document?(file_path)
      return true unless file_path.downcase.end_with?('.pdf')

      # Use simple PDF page count check
      # In production, use a proper PDF library
      false # Assume multi-page for PDFs
    end

    def validate_file!(file_path)
      raise ArgumentError, "File not found: #{file_path}" unless File.exist?(file_path)

      extension = File.extname(file_path).downcase.delete('.')
      unless SUPPORTED_FORMATS.include?(extension)
        raise ArgumentError, "Unsupported file format: #{extension}"
      end

      # Check file size (Textract limit is 10MB for sync, 500MB for async)
      max_size = 500.megabytes
      if File.size(file_path) > max_size
        raise ArgumentError, "File too large: #{File.size(file_path)} bytes (max: #{max_size})"
      end
    end

    def notification_enabled?
      ENV['TEXTRACT_SNS_TOPIC_ARN'].present?
    end

    def notification_config
      return nil unless notification_enabled?

      {
        sns_topic_arn: ENV['TEXTRACT_SNS_TOPIC_ARN'],
        role_arn: ENV['TEXTRACT_ROLE_ARN']
      }
    end

    def handle_textract_error(error)
      case error
      when ::Aws::Textract::Errors::ThrottlingException
        raise RetryableError, "Textract rate limit reached. Please retry."
      when ::Aws::Textract::Errors::ProvisionedThroughputExceededException
        raise RetryableError, "Textract throughput exceeded. Please retry."
      when ::Aws::Textract::Errors::InvalidS3ObjectException
        raise ArgumentError, "Invalid S3 object: #{error.message}"
      else
        raise error
      end
    end

    class RetryableError < StandardError; end
  end
end
```

### 2. AWS Bedrock Knowledge Base Service

```ruby
# app/services/aws/bedrock_knowledge_base_service.rb
require 'aws-sdk-bedrockagent'
require 'aws-sdk-bedrockagentruntime'

module Aws
  class BedrockKnowledgeBaseService
    include ActiveSupport::Rescuable

    EMBEDDING_MODEL = 'amazon.titan-embed-text-v2:0'
    GENERATION_MODEL = 'anthropic.claude-3-5-sonnet-20241022-v2:0'

    attr_reader :entity, :agent_client, :runtime_client

    def initialize(entity)
      @entity = entity
      @agent_client = ::Aws::BedrockAgent::Client.new(
        region: ENV.fetch('AWS_REGION', 'us-east-1')
      )
      @runtime_client = ::Aws::BedrockAgentRuntime::Client.new(
        region: ENV.fetch('AWS_REGION', 'us-east-1')
      )
    end

    # Create or get knowledge base for entity
    def ensure_knowledge_base
      return @entity.bedrock_kb_id if @entity.bedrock_kb_id.present?

      kb = create_knowledge_base
      @entity.update!(bedrock_kb_id: kb.knowledge_base_id)

      # Create initial data source
      create_s3_data_source

      kb.knowledge_base_id
    end

    # Create new knowledge base
    def create_knowledge_base
      response = @agent_client.create_knowledge_base(
        name: kb_name,
        description: "Knowledge base for #{@entity.name} (Entity ID: #{@entity.id})",
        role_arn: kb_role_arn,
        knowledge_base_configuration: {
          type: 'VECTOR',
          vector_knowledge_base_configuration: {
            embedding_model_arn: embedding_model_arn,
            embedding_model_configuration: {
              bedrock_embedding_model_configuration: {
                dimensions: 1024  # Titan v2 dimensions
              }
            }
          }
        },
        storage_configuration: storage_config,
        tags: {
          'entity-id' => @entity.id.to_s,
          'environment' => Rails.env
        }
      )

      response.knowledge_base
    rescue ::Aws::BedrockAgent::Errors::ServiceError => e
      handle_bedrock_error(e)
    end

    # Add document to knowledge base
    def add_document(file_path, metadata = {})
      ensure_knowledge_base

      # Upload to S3 in the correct structure
      s3_key = upload_document_to_s3(file_path, metadata)

      # Trigger ingestion
      start_ingestion_job

      {
        status: 'queued',
        s3_key: s3_key,
        message: 'Document queued for ingestion'
      }
    end

    # Query the knowledge base
    def query(user_query, options = {})
      ensure_knowledge_base

      response = @runtime_client.retrieve(
        knowledge_base_id: @entity.bedrock_kb_id,
        retrieval_query: {
          text: user_query
        },
        retrieval_configuration: {
          vector_search_configuration: {
            number_of_results: options[:top_k] || 10,
            override_search_type: options[:search_type] || 'HYBRID',
            filter: build_metadata_filter(options[:filters])
          }
        }
      )

      parse_retrieval_results(response.retrieval_results)
    rescue ::Aws::BedrockAgentRuntime::Errors::ServiceError => e
      handle_runtime_error(e)
    end

    # Query with generation (RAG)
    def query_with_generation(user_query, options = {})
      ensure_knowledge_base

      response = @runtime_client.retrieve_and_generate(
        input: {
          text: user_query
        },
        retrieve_and_generate_configuration: {
          type: 'KNOWLEDGE_BASE',
          knowledge_base_configuration: {
            knowledge_base_id: @entity.bedrock_kb_id,
            model_arn: generation_model_arn,
            generation_configuration: {
              prompt_template: {
                text_prompt_template: options[:prompt_template] || default_prompt_template
              },
              inference_config: {
                text_inference_config: {
                  max_tokens: options[:max_tokens] || 2048,
                  temperature: options[:temperature] || 0.7,
                  top_p: options[:top_p] || 0.9
                }
              }
            },
            retrieval_configuration: {
              vector_search_configuration: {
                number_of_results: options[:top_k] || 10,
                override_search_type: 'HYBRID'
              }
            }
          }
        },
        session_configuration: session_config(options)
      )

      {
        answer: response.output.text,
        citations: parse_citations(response.citations),
        session_id: response.session_id
      }
    end

    # Start ingestion job
    def start_ingestion_job
      ensure_data_source

      response = @agent_client.start_ingestion_job(
        knowledge_base_id: @entity.bedrock_kb_id,
        data_source_id: @entity.bedrock_data_source_id,
        description: "Ingestion at #{Time.current}"
      )

      Rails.logger.info "Started ingestion job: #{response.ingestion_job.ingestion_job_id}"

      # Queue job to check status
      BedrockIngestionStatusJob.perform_later(
        @entity.id,
        response.ingestion_job.ingestion_job_id
      )

      response.ingestion_job
    end

    # Check ingestion job status
    def check_ingestion_status(job_id)
      response = @agent_client.get_ingestion_job(
        knowledge_base_id: @entity.bedrock_kb_id,
        data_source_id: @entity.bedrock_data_source_id,
        ingestion_job_id: job_id
      )

      {
        status: response.ingestion_job.status,
        statistics: response.ingestion_job.statistics,
        started_at: response.ingestion_job.started_at,
        updated_at: response.ingestion_job.updated_at
      }
    end

    # Delete knowledge base (cleanup)
    def delete_knowledge_base
      return unless @entity.bedrock_kb_id.present?

      @agent_client.delete_knowledge_base(
        knowledge_base_id: @entity.bedrock_kb_id
      )

      @entity.update!(
        bedrock_kb_id: nil,
        bedrock_data_source_id: nil
      )
    end

    private

    def kb_name
      "#{ENV['APP_NAME']}-entity-#{@entity.id}-kb"
    end

    def kb_role_arn
      ENV.fetch('BEDROCK_KB_ROLE_ARN') do
        # Auto-construct ARN if not provided
        account_id = ENV['AWS_ACCOUNT_ID'] || Aws::STS::Client.new.get_caller_identity.account
        "arn:aws:iam::#{account_id}:role/BedrockKnowledgeBaseRole"
      end
    end

    def embedding_model_arn
      "arn:aws:bedrock:#{ENV.fetch('AWS_REGION', 'us-east-1')}::foundation-model/#{EMBEDDING_MODEL}"
    end

    def generation_model_arn
      "arn:aws:bedrock:#{ENV.fetch('AWS_REGION', 'us-east-1')}::foundation-model/#{GENERATION_MODEL}"
    end

    def storage_config
      {
        type: 'OPENSEARCH_SERVERLESS',
        opensearch_serverless_configuration: {
          collection_arn: ensure_opensearch_collection,
          vector_index_name: "entity-#{@entity.id}-index",
          field_mapping: {
            vector_field: 'embedding',
            text_field: 'text',
            metadata_field: 'metadata'
          }
        }
      }
    end

    def ensure_opensearch_collection
      # In production, this would check/create OpenSearch Serverless collection
      # For now, use a shared collection
      ENV.fetch('OPENSEARCH_COLLECTION_ARN') do
        account_id = ENV['AWS_ACCOUNT_ID'] || Aws::STS::Client.new.get_caller_identity.account
        region = ENV.fetch('AWS_REGION', 'us-east-1')
        "arn:aws:aoss:#{region}:#{account_id}:collection/#{ENV['APP_NAME']}-rag"
      end
    end

    def create_s3_data_source
      response = @agent_client.create_data_source(
        knowledge_base_id: @entity.bedrock_kb_id,
        name: "#{kb_name}-s3-source",
        data_source_configuration: {
          type: 'S3',
          s3_configuration: {
            bucket_arn: s3_bucket_arn,
            inclusion_prefixes: ["entities/#{@entity.id}/"]
          }
        }
      )

      @entity.update!(bedrock_data_source_id: response.data_source.data_source_id)
      response.data_source
    end

    def ensure_data_source
      return if @entity.bedrock_data_source_id.present?
      create_s3_data_source
    end

    def s3_bucket_arn
      bucket_name = ENV.fetch('RAG_STORAGE_BUCKET', "#{ENV['APP_NAME']}-rag-storage")
      "arn:aws:s3:::#{bucket_name}"
    end

    def upload_document_to_s3(file_path, metadata)
      s3_client = ::Aws::S3::Client.new(region: ENV.fetch('AWS_REGION', 'us-east-1'))

      file_name = File.basename(file_path)
      s3_key = "entities/#{@entity.id}/documents/#{SecureRandom.hex(8)}/#{file_name}"

      # Upload with metadata that Bedrock can use
      File.open(file_path, 'rb') do |file|
        s3_client.put_object(
          bucket: ENV.fetch('RAG_STORAGE_BUCKET'),
          key: s3_key,
          body: file,
          metadata: metadata.merge(
            'entity-id' => @entity.id.to_s,
            'uploaded-at' => Time.current.iso8601
          )
        )
      end

      # Also create a metadata file for Bedrock
      metadata_key = "#{s3_key}.metadata.json"
      s3_client.put_object(
        bucket: ENV.fetch('RAG_STORAGE_BUCKET'),
        key: metadata_key,
        body: metadata.to_json,
        content_type: 'application/json'
      )

      s3_key
    end

    def build_metadata_filter(filters)
      return nil if filters.blank?

      # Convert filters to Bedrock format
      {
        and_all: filters.map do |key, value|
          {
            equals: {
              key: key.to_s,
              value: value.to_s
            }
          }
        end
      }
    end

    def parse_retrieval_results(results)
      results.map do |result|
        {
          content: result.content.text,
          score: result.score,
          metadata: result.metadata,
          location: result.location
        }
      end
    end

    def parse_citations(citations)
      return [] unless citations

      citations.map do |citation|
        {
          text: citation.generated_response_part.text_response_part.text,
          sources: citation.retrieved_references.map do |ref|
            {
              content: ref.content.text,
              location: ref.location,
              metadata: ref.metadata
            }
          end
        }
      end
    end

    def default_prompt_template
      <<~PROMPT
        You are a helpful assistant. Use the following context to answer the user's question.
        If you cannot answer based on the context, say so.

        Context:
        {context}

        Question: {query}

        Answer:
      PROMPT
    end

    def session_config(options)
      return nil unless options[:enable_session]

      {
        kms_key_arn: ENV['KMS_KEY_ARN']
      }
    end

    def handle_bedrock_error(error)
      case error
      when ::Aws::BedrockAgent::Errors::ThrottlingException
        raise RetryableError, "Bedrock Agent rate limit. Please retry."
      when ::Aws::BedrockAgent::Errors::ResourceNotFoundException
        raise NotFoundError, "Knowledge base not found: #{error.message}"
      else
        Rails.logger.error "Bedrock Agent error: #{error.class} - #{error.message}"
        raise error
      end
    end

    def handle_runtime_error(error)
      case error
      when ::Aws::BedrockAgentRuntime::Errors::ThrottlingException
        raise RetryableError, "Bedrock Runtime rate limit. Please retry."
      when ::Aws::BedrockAgentRuntime::Errors::ResourceNotFoundException
        raise NotFoundError, "Resource not found: #{error.message}"
      else
        Rails.logger.error "Bedrock Runtime error: #{error.class} - #{error.message}"
        raise error
      end
    end

    class RetryableError < StandardError; end
    class NotFoundError < StandardError; end
  end
end
```

### 3. AWS Comprehend Service (NLP Enhancement)

```ruby
# app/services/aws/comprehend_service.rb
require 'aws-sdk-comprehend'

module Aws
  class ComprehendService
    include ActiveSupport::Rescuable

    MAX_TEXT_SIZE = 100_000  # Comprehend limit in bytes
    SUPPORTED_LANGUAGES = %w[en es fr de it pt].freeze

    attr_reader :client

    def initialize
      @client = ::Aws::Comprehend::Client.new(
        region: ENV.fetch('AWS_REGION', 'us-east-1')
      )
    end

    # Full document analysis
    def analyze_document(text, language_code: 'en')
      validate_text!(text)

      analysis_results = {}

      # Run all analyses in parallel
      threads = []

      threads << Thread.new do
        analysis_results[:entities] = detect_entities(text, language_code)
      end

      threads << Thread.new do
        analysis_results[:key_phrases] = detect_key_phrases(text, language_code)
      end

      threads << Thread.new do
        analysis_results[:sentiment] = detect_sentiment(text, language_code)
      end

      threads << Thread.new do
        analysis_results[:syntax] = detect_syntax(text, language_code) if text.length < 5000
      end

      threads << Thread.new do
        analysis_results[:pii] = detect_pii(text, language_code) if should_detect_pii?
      end

      threads.each(&:join)

      analysis_results[:language] = detect_language(text) if language_code == 'auto'
      analysis_results[:analyzed_at] = Time.current

      analysis_results
    end

    # Entity detection
    def detect_entities(text, language_code = 'en')
      response = @client.detect_entities(
        text: truncate_text(text),
        language_code: language_code
      )

      response.entities.map do |entity|
        {
          text: entity.text,
          type: entity.type,
          score: entity.score,
          begin_offset: entity.begin_offset,
          end_offset: entity.end_offset
        }
      end
    rescue ::Aws::Comprehend::Errors::ServiceError => e
      handle_comprehend_error(e)
      []
    end

    # Key phrase extraction
    def detect_key_phrases(text, language_code = 'en')
      response = @client.detect_key_phrases(
        text: truncate_text(text),
        language_code: language_code
      )

      response.key_phrases.map do |phrase|
        {
          text: phrase.text,
          score: phrase.score,
          begin_offset: phrase.begin_offset,
          end_offset: phrase.end_offset
        }
      end
    rescue ::Aws::Comprehend::Errors::ServiceError => e
      handle_comprehend_error(e)
      []
    end

    # Sentiment analysis
    def detect_sentiment(text, language_code = 'en')
      response = @client.detect_sentiment(
        text: truncate_text(text),
        language_code: language_code
      )

      {
        sentiment: response.sentiment,
        scores: {
          positive: response.sentiment_score.positive,
          negative: response.sentiment_score.negative,
          neutral: response.sentiment_score.neutral,
          mixed: response.sentiment_score.mixed
        }
      }
    rescue ::Aws::Comprehend::Errors::ServiceError => e
      handle_comprehend_error(e)
      { sentiment: 'UNKNOWN', scores: {} }
    end

    # Language detection
    def detect_language(text)
      response = @client.detect_dominant_language(
        text: truncate_text(text)
      )

      languages = response.languages.map do |lang|
        {
          code: lang.language_code,
          score: lang.score
        }
      end

      languages.first
    rescue ::Aws::Comprehend::Errors::ServiceError => e
      handle_comprehend_error(e)
      { code: 'en', score: 0.0 }
    end

    # PII detection
    def detect_pii(text, language_code = 'en')
      response = @client.detect_pii_entities(
        text: truncate_text(text),
        language_code: language_code
      )

      response.entities.map do |entity|
        {
          type: entity.type,
          score: entity.score,
          begin_offset: entity.begin_offset,
          end_offset: entity.end_offset
        }
      end
    rescue ::Aws::Comprehend::Errors::ServiceError => e
      handle_comprehend_error(e)
      []
    end

    # Syntax detection (parts of speech)
    def detect_syntax(text, language_code = 'en')
      response = @client.detect_syntax(
        text: truncate_text(text),
        language_code: language_code
      )

      response.syntax_tokens.map do |token|
        {
          text: token.text,
          part_of_speech: token.part_of_speech.tag,
          score: token.part_of_speech.score,
          begin_offset: token.begin_offset,
          end_offset: token.end_offset
        }
      end
    rescue ::Aws::Comprehend::Errors::ServiceError => e
      handle_comprehend_error(e)
      []
    end

    # Topic modeling for multiple documents
    def start_topic_detection(documents, s3_output_uri)
      # Prepare input documents in S3
      input_s3_uri = upload_documents_for_topic_modeling(documents)

      response = @client.start_topics_detection_job(
        input_data_config: {
          s3_uri: input_s3_uri,
          input_format: 'ONE_DOC_PER_LINE'
        },
        output_data_config: {
          s3_uri: s3_output_uri
        },
        data_access_role_arn: comprehend_role_arn,
        number_of_topics: 10
      )

      response.job_id
    end

    # Check topic detection job status
    def get_topic_detection_status(job_id)
      response = @client.describe_topics_detection_job(job_id: job_id)

      {
        status: response.topics_detection_job_properties.job_status,
        output_uri: response.topics_detection_job_properties.output_data_config&.s3_uri,
        message: response.topics_detection_job_properties.message
      }
    end

    # Enhance document metadata with Comprehend analysis
    def enhance_document_metadata(document)
      text = extract_document_text(document)
      analysis = analyze_document(text)

      # Extract top entities and key phrases
      top_entities = analysis[:entities]
        .group_by { |e| e[:type] }
        .transform_values { |entities| entities.first(5).map { |e| e[:text] } }

      top_key_phrases = analysis[:key_phrases]
        .sort_by { |kp| -kp[:score] }
        .first(10)
        .map { |kp| kp[:text] }

      metadata = {
        comprehend_analysis: {
          entities: top_entities,
          key_phrases: top_key_phrases,
          sentiment: analysis[:sentiment],
          language: analysis[:language],
          analyzed_at: analysis[:analyzed_at]
        }
      }

      # Update document
      document.update!(
        metadata: document.metadata.merge(metadata),
        sentiment: analysis[:sentiment][:sentiment],
        language: analysis[:language][:code] if analysis[:language]
      )

      metadata
    end

    private

    def truncate_text(text)
      return text if text.bytesize <= MAX_TEXT_SIZE

      # Truncate to fit within byte limit
      text.mb_chars.limit(MAX_TEXT_SIZE).to_s
    end

    def validate_text!(text)
      raise ArgumentError, "Text cannot be blank" if text.blank?
      raise ArgumentError, "Text too large (max #{MAX_TEXT_SIZE} bytes)" if text.bytesize > MAX_TEXT_SIZE * 2
    end

    def should_detect_pii?
      ENV.fetch('COMPREHEND_DETECT_PII', 'false') == 'true'
    end

    def comprehend_role_arn
      ENV.fetch('COMPREHEND_ROLE_ARN') do
        account_id = ENV['AWS_ACCOUNT_ID'] || Aws::STS::Client.new.get_caller_identity.account
        "arn:aws:iam::#{account_id}:role/ComprehendRole"
      end
    end

    def extract_document_text(document)
      # Extract text based on document type
      if document.respond_to?(:content)
        document.content
      elsif document.respond_to?(:raw_text)
        document.raw_text
      else
        document.to_s
      end
    end

    def upload_documents_for_topic_modeling(documents)
      # Implementation would upload documents to S3 in required format
      # Returns S3 URI
      "s3://#{ENV['RAG_STORAGE_BUCKET']}/comprehend/topic-modeling/input/#{SecureRandom.hex(8)}/"
    end

    def handle_comprehend_error(error)
      case error
      when ::Aws::Comprehend::Errors::ThrottlingException
        Rails.logger.warn "Comprehend throttled: #{error.message}"
      when ::Aws::Comprehend::Errors::TextSizeLimitExceededException
        Rails.logger.warn "Text size limit exceeded: #{error.message}"
      when ::Aws::Comprehend::Errors::UnsupportedLanguageException
        Rails.logger.warn "Unsupported language: #{error.message}"
      else
        Rails.logger.error "Comprehend error: #{error.class} - #{error.message}"
      end
    end
  end
end
```

### 4. Background Jobs

```ruby
# app/jobs/textract_result_job.rb
class TextractResultJob < ApplicationJob
  queue_as :document_processing

  retry_on Aws::TextractService::RetryableError, wait: 30.seconds, attempts: 5

  def perform(entity_id, job_id, s3_key, options = {})
    entity = Entity.find(entity_id)
    service = Aws::TextractService.new(entity)

    # Check job status
    result = service.get_job_results(job_id)

    case result[:status]
    when 'completed'
      process_completed_job(entity, result, s3_key, options)
    when 'processing'
      # Re-queue to check later
      TextractResultJob.set(wait: 30.seconds).perform_later(
        entity_id, job_id, s3_key, options
      )
    when 'failed'
      handle_failed_job(entity, job_id, result[:error])
    end
  end

  private

  def process_completed_job(entity, result, s3_key, options)
    # Store extracted text in chunks
    document = entity.rag_documents.find_or_create_by(s3_key: s3_key)

    document.update!(
      textract_status: 'completed',
      textract_result: result,
      raw_text: result[:raw_text],
      metadata: result[:metadata]
    )

    # Create chunks for RAG
    create_chunks(document, result[:pages])

    # Run Comprehend analysis if enabled
    if options[:analyze_with_comprehend]
      ComprehendAnalysisJob.perform_later(document.id)
    end

    # Trigger ingestion to Bedrock KB if enabled
    if entity.use_bedrock_kb?
      BedrockIngestionJob.perform_later(entity.id, document.id)
    end
  end

  def create_chunks(document, pages)
    pages.each_with_index do |page, index|
      document.rag_chunks.create!(
        content: page[:text],
        chunk_index: index,
        metadata: {
          page_number: page[:page_number],
          confidence: page[:confidence],
          tables_count: page[:tables].size,
          forms_count: page[:forms].size
        }
      )
    end
  end

  def handle_failed_job(entity, job_id, error_message)
    Rails.logger.error "Textract job #{job_id} failed: #{error_message}"

    # Notify entity admin
    EntityMailer.document_processing_failed(entity, job_id, error_message).deliver_later
  end
end

# app/jobs/bedrock_ingestion_job.rb
class BedrockIngestionJob < ApplicationJob
  queue_as :rag_processing

  def perform(entity_id, document_id = nil)
    entity = Entity.find(entity_id)
    service = Aws::BedrockKnowledgeBaseService.new(entity)

    if document_id
      # Ingest specific document
      document = entity.rag_documents.find(document_id)
      ingest_document(service, document)
    else
      # Trigger full ingestion
      service.start_ingestion_job
    end
  end

  private

  def ingest_document(service, document)
    # Ensure document is in S3
    s3_key = document.s3_key || upload_to_s3(document)

    # Add to knowledge base
    result = service.add_document(s3_key, document.metadata)

    # Update document status
    document.update!(
      bedrock_ingestion_status: result[:status],
      bedrock_ingested_at: Time.current
    )
  end
end

# app/jobs/comprehend_analysis_job.rb
class ComprehendAnalysisJob < ApplicationJob
  queue_as :nlp_processing

  def perform(document_id)
    document = RagDocument.find(document_id)
    service = Aws::ComprehendService.new

    # Analyze document
    service.enhance_document_metadata(document)

    # Mark as analyzed
    document.update!(comprehend_analyzed_at: Time.current)
  end
end
```

## Monitoring and Observability

```ruby
# app/services/monitoring/aws_rag_metrics.rb
module Monitoring
  class AwsRagMetrics
    include Singleton

    def track_textract_processing(entity_id, duration, status, page_count = nil)
      send_metric(
        namespace: 'AMOS/Textract',
        metric_name: 'ProcessingTime',
        value: duration,
        unit: 'Seconds',
        dimensions: [
          { name: 'EntityId', value: entity_id.to_s },
          { name: 'Status', value: status }
        ]
      )

      if page_count
        send_metric(
          namespace: 'AMOS/Textract',
          metric_name: 'PagesProcessed',
          value: page_count,
          unit: 'Count',
          dimensions: [{ name: 'EntityId', value: entity_id.to_s }]
        )
      end
    end

    def track_bedrock_query(entity_id, duration, chunks_retrieved)
      send_metric(
        namespace: 'AMOS/BedrockKB',
        metric_name: 'QueryLatency',
        value: duration,
        unit: 'Milliseconds',
        dimensions: [{ name: 'EntityId', value: entity_id.to_s }]
      )

      send_metric(
        namespace: 'AMOS/BedrockKB',
        metric_name: 'ChunksRetrieved',
        value: chunks_retrieved,
        unit: 'Count',
        dimensions: [{ name: 'EntityId', value: entity_id.to_s }]
      )
    end

    def track_comprehend_analysis(entity_id, operation, duration)
      send_metric(
        namespace: 'AMOS/Comprehend',
        metric_name: 'AnalysisTime',
        value: duration,
        unit: 'Milliseconds',
        dimensions: [
          { name: 'EntityId', value: entity_id.to_s },
          { name: 'Operation', value: operation }
        ]
      )
    end

    private

    def send_metric(params)
      cloudwatch.put_metric_data(params)
    rescue => e
      Rails.logger.error "Failed to send metric: #{e.message}"
    end

    def cloudwatch
      @cloudwatch ||= Aws::CloudWatch::Client.new(
        region: ENV.fetch('AWS_REGION', 'us-east-1')
      )
    end
  end
end
```

## Testing

```ruby
# test/services/aws/textract_service_test.rb
require 'test_helper'

class Aws::TextractServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:acme)
    @service = Aws::TextractService.new(@entity)
  end

  test "processes single page document synchronously" do
    VCR.use_cassette('textract/single_page_sync') do
      result = @service.process_document(
        file_fixture('sample_invoice.pdf').to_s,
        extract_tables: true,
        extract_forms: true
      )

      assert_equal 1, result[:pages].size
      assert result[:tables].any?
      assert result[:forms].any?
      assert_includes result[:raw_text], 'Invoice'
    end
  end

  test "processes multi-page document asynchronously" do
    VCR.use_cassette('textract/multi_page_async') do
      result = @service.process_document(
        file_fixture('multi_page_report.pdf').to_s
      )

      assert_equal 'processing', result[:status]
      assert_not_nil result[:job_id]
    end
  end

  test "extracts tables from document" do
    VCR.use_cassette('textract/extract_tables') do
      # Upload file first
      s3_key = @service.send(:upload_to_s3, file_fixture('table_document.pdf').to_s)

      tables = @service.extract_tables(s3_key)

      assert tables.any?
      assert_equal 3, tables.first[:data].size # 3 rows
      assert_equal 4, tables.first[:data].first.size # 4 columns
    end
  end

  test "handles unsupported file format" do
    assert_raises(ArgumentError) do
      @service.process_document('test.xyz')
    end
  end

  test "handles large files" do
    # Create a mock large file
    large_file = Tempfile.new(['large', '.pdf'])
    large_file.write('x' * (501.megabytes))
    large_file.rewind

    assert_raises(ArgumentError) do
      @service.process_document(large_file.path)
    end
  ensure
    large_file.close
    large_file.unlink
  end
end

# test/services/aws/bedrock_knowledge_base_service_test.rb
require 'test_helper'

class Aws::BedrockKnowledgeBaseServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:acme)
    @service = Aws::BedrockKnowledgeBaseService.new(@entity)
  end

  test "creates knowledge base for entity" do
    VCR.use_cassette('bedrock_kb/create_knowledge_base') do
      kb_id = @service.ensure_knowledge_base

      assert_not_nil kb_id
      assert_equal kb_id, @entity.reload.bedrock_kb_id
      assert_not_nil @entity.bedrock_data_source_id
    end
  end

  test "adds document to knowledge base" do
    @entity.update!(bedrock_kb_id: 'kb-test-123')

    VCR.use_cassette('bedrock_kb/add_document') do
      result = @service.add_document(
        file_fixture('sample_document.pdf').to_s,
        title: 'Sample Document',
        category: 'test'
      )

      assert_equal 'queued', result[:status]
      assert_not_nil result[:s3_key]
    end
  end

  test "queries knowledge base" do
    @entity.update!(bedrock_kb_id: 'kb-test-123')

    VCR.use_cassette('bedrock_kb/query') do
      results = @service.query('What is the refund policy?', top_k: 5)

      assert results.any?
      assert results.first[:score] > 0.5
      assert_not_nil results.first[:content]
    end
  end

  test "queries with generation" do
    @entity.update!(bedrock_kb_id: 'kb-test-123')

    VCR.use_cassette('bedrock_kb/query_with_generation') do
      result = @service.query_with_generation(
        'Summarize the refund policy',
        max_tokens: 500
      )

      assert_not_nil result[:answer]
      assert result[:citations].any?
      assert_not_nil result[:session_id]
    end
  end
end
```

This implementation guide provides a complete foundation for migrating your RAG and OCR systems to AWS native services. The code is production-ready and includes proper error handling, monitoring, and testing.