# app/services/aws/bedrock_knowledge_base_service.rb
require 'aws-sdk-bedrockagent'
require 'aws-sdk-bedrockagentruntime'
require 'aws-sdk-opensearchservice'
require 'aws-sdk-s3'

module Aws
  class BedrockKnowledgeBaseService
    include Singleton

    attr_reader :bedrock_agent_client, :bedrock_runtime_client, :s3_client

    EMBEDDING_MODEL_ARN = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
    CHUNK_SIZE = 512  # tokens
    CHUNK_OVERLAP = 100  # tokens

    def initialize
      @bedrock_agent_client = Aws::BedrockAgent::Client.new(
        region: ENV.fetch('AWS_REGION', 'us-east-1'),
        credentials: credentials
      )

      @bedrock_runtime_client = Aws::BedrockAgentRuntime::Client.new(
        region: ENV.fetch('AWS_REGION', 'us-east-1'),
        credentials: credentials
      )

      @s3_client = Aws::S3::Client.new(
        region: ENV.fetch('AWS_REGION', 'us-east-1'),
        credentials: credentials
      )

      @opensearch_client = Aws::OpenSearchService::Client.new(
        region: ENV.fetch('AWS_REGION', 'us-east-1'),
        credentials: credentials
      )
    end

    # Create or get existing knowledge base for an entity
    def create_knowledge_base(entity)
      kb_name = "entity-#{entity.id}-kb"

      # Check if KB already exists
      existing_kb = find_knowledge_base(kb_name)
      return existing_kb if existing_kb

      # Create S3 data source bucket if needed
      bucket_name = ensure_s3_bucket(entity)

      # Create OpenSearch Serverless collection
      collection_arn = ensure_opensearch_collection(entity)

      # Create the knowledge base
      response = @bedrock_agent_client.create_knowledge_base({
        name: kb_name,
        description: "Knowledge base for entity #{entity.name} (ID: #{entity.id})",
        role_arn: knowledge_base_role_arn,
        knowledge_base_configuration: {
          type: "VECTOR",
          vector_knowledge_base_configuration: {
            embedding_model_arn: EMBEDDING_MODEL_ARN,
            embedding_model_configuration: {
              bedrock_embedding_model_configuration: {
                dimensions: 1024  # Titan v2 embedding dimensions
              }
            }
          }
        },
        storage_configuration: {
          type: "OPENSEARCH_SERVERLESS",
          opensearch_serverless_configuration: {
            collection_arn: collection_arn,
            vector_index_name: "entity-#{entity.id}-index",
            field_mapping: {
              vector_field: "embedding",
              text_field: "text",
              metadata_field: "metadata"
            }
          }
        },
        tags: {
          'Entity' => entity.id.to_s,
          'Environment' => ::Rails.env,
          'Service' => 'KnowledgeBase'
        }
      })

      kb = response.knowledge_base

      # Create S3 data source for the knowledge base
      create_data_source(kb.knowledge_base_id, bucket_name, entity)

      # Store KB ID in entity
      entity.update!(
        bedrock_knowledge_base_id: kb.knowledge_base_id,
        bedrock_kb_status: 'CREATING'
      )

      # Start sync job
      start_ingestion_job(kb.knowledge_base_id, entity)

      ::Rails.logger.info "Created knowledge base #{kb.knowledge_base_id} for entity #{entity.id}"

      kb
    rescue => e
      ::Rails.logger.error "Failed to create knowledge base: #{e.message}"
      raise
    end

    # Add document to knowledge base
    def add_document(entity, file_path, metadata = {})
      ensure_knowledge_base(entity)

      # Upload to S3
      s3_key = upload_document_to_s3(entity, file_path, metadata)

      # Create metadata file for the document
      create_metadata_file(entity, s3_key, metadata)

      # Trigger ingestion
      start_ingestion_job(entity.bedrock_knowledge_base_id, entity)

      # Note: Bedrock KB manages document tracking internally via S3 sync
      # We track ingestion jobs at the entity level via bedrock_last_ingestion_job_id

      ::Rails.logger.info "Added document #{s3_key} to knowledge base for entity #{entity.id}"

      { success: true, s3_key: s3_key }
    rescue => e
      ::Rails.logger.error "Failed to add document: #{e.message}"
      { success: false, error: e.message }
    end

    # Query knowledge base
    def query(entity, query_text, options = {})
      ensure_knowledge_base(entity)

      max_results = options[:max_results] || 5
      search_type = options[:search_type] || 'HYBRID'  # HYBRID, SEMANTIC, or HYBRID

      response = @bedrock_runtime_client.retrieve({
        knowledge_base_id: entity.bedrock_knowledge_base_id,
        retrieval_query: {
          text: query_text
        },
        retrieval_configuration: {
          vector_search_configuration: {
            number_of_results: max_results,
            override_search_type: search_type,
            filter: build_metadata_filter(options[:filters])
          }
        }
      })

      # Process results
      results = response.retrieval_results.map do |result|
        {
          content: result.content.text,
          score: result.score,
          metadata: result.metadata,
          location: result.location,
          chunk_id: result.retrieval_result_id
        }
      end

      # Track usage for cost tracking
      track_retrieval_usage(entity, query_text, results.count)

      {
        query: query_text,
        results: results,
        result_count: results.count,
        search_type: search_type
      }
    rescue => e
      ::Rails.logger.error "Query failed: #{e.message}"
      { query: query_text, results: [], error: e.message }
    end

    # Retrieve and generate response using the knowledge base
    def retrieve_and_generate(entity, query_text, session_id = nil, options = {})
      ensure_knowledge_base(entity)

      model_arn = options[:model_arn] || "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-sonnet-4-6"
      max_tokens = options[:max_tokens] || 2048

      request = {
        knowledge_base_id: entity.bedrock_knowledge_base_id,
        model_arn: model_arn,
        input: {
          text: query_text
        },
        retrieval_configuration: {
          vector_search_configuration: {
            number_of_results: options[:max_results] || 5,
            override_search_type: options[:search_type] || 'HYBRID'
          }
        },
        generation_configuration: {
          prompt_template: {
            text_prompt_template: build_prompt_template(options[:system_prompt])
          },
          inference_config: {
            text_inference_config: {
              max_tokens: max_tokens,
              temperature: options[:temperature] || 0.7,
              top_p: options[:top_p] || 0.9
            }
          }
        }
      }

      # Add session if provided for conversation continuity
      if session_id
        request[:session_id] = session_id
        session_config = {}
        session_config[:kms_key_id] = ENV['KMS_KEY_ID'] if ENV['KMS_KEY_ID']
        request[:session_configuration] = session_config if session_config.any?
      end

      response = @bedrock_runtime_client.retrieve_and_generate(request)

      # Track usage
      track_generation_usage(entity, query_text, response)

      {
        response: response.output.text,
        session_id: response.session_id,
        citations: parse_citations(response.citations),
        retrieval_results: response.retrieval_results&.map { |r|
          {
            content: r.content.text,
            score: r.score,
            metadata: r.metadata
          }
        }
      }
    rescue => e
      ::Rails.logger.error "Retrieve and generate failed: #{e.message}"
      { response: nil, error: e.message }
    end

    # Delete document from knowledge base
    def delete_document(entity, document_id)
      ensure_knowledge_base(entity)

      # Find the document
      doc = entity.rag_documents.find(document_id)
      s3_key = doc.metadata['s3_key']

      if s3_key
        # Delete from S3
        @s3_client.delete_object({
          bucket: bucket_name(entity),
          key: s3_key
        })

        # Delete metadata file
        @s3_client.delete_object({
          bucket: bucket_name(entity),
          key: "#{s3_key}.metadata.json"
        })

        # Trigger sync to update the knowledge base
        start_ingestion_job(entity.bedrock_knowledge_base_id, entity)
      end

      # Mark as deleted in database
      doc.update!(
        processing_status: 'deleted',
        deleted_at: Time.current
      )

      { success: true }
    rescue => e
      ::Rails.logger.error "Failed to delete document: #{e.message}"
      { success: false, error: e.message }
    end

    # Start ingestion job to sync S3 with knowledge base
    def start_ingestion_job(knowledge_base_id, entity)
      # Find the data source ID
      data_sources = @bedrock_agent_client.list_data_sources({
        knowledge_base_id: knowledge_base_id,
        max_results: 10
      })

      return unless data_sources.data_source_summaries.any?

      data_source_id = data_sources.data_source_summaries.first.data_source_id

      response = @bedrock_agent_client.start_ingestion_job({
        knowledge_base_id: knowledge_base_id,
        data_source_id: data_source_id,
        description: "Ingestion for entity #{entity.id} at #{Time.current}"
      })

      ::Rails.logger.info "Started ingestion job #{response.ingestion_job.ingestion_job_id}"

      # Store job ID for tracking
      entity.update!(
        bedrock_last_ingestion_job_id: response.ingestion_job.ingestion_job_id
      )

      response.ingestion_job
    rescue => e
      ::Rails.logger.error "Failed to start ingestion job: #{e.message}"
      nil
    end

    # Check ingestion job status
    def check_ingestion_status(entity)
      return nil unless entity.bedrock_last_ingestion_job_id

      response = @bedrock_agent_client.get_ingestion_job({
        knowledge_base_id: entity.bedrock_knowledge_base_id,
        data_source_id: get_data_source_id(entity),
        ingestion_job_id: entity.bedrock_last_ingestion_job_id
      })

      job = response.ingestion_job

      {
        job_id: job.ingestion_job_id,
        status: job.status,
        started_at: job.started_at,
        updated_at: job.updated_at,
        statistics: {
          documents_scanned: job.statistics.number_of_documents_scanned,
          documents_indexed: job.statistics.number_of_documents_indexed,
          documents_failed: job.statistics.number_of_documents_failed,
          documents_deleted: job.statistics.number_of_documents_deleted
        },
        failure_reasons: job.failure_reasons
      }
    rescue => e
      ::Rails.logger.error "Failed to check ingestion status: #{e.message}"
      nil
    end


    # List all documents in the knowledge base
    def list_documents(entity, options = {})
      ensure_knowledge_base(entity)

      prefix = options[:prefix] || "documents/#{entity.id}/"
      max_keys = options[:max_keys] || 100

      response = @s3_client.list_objects_v2({
        bucket: bucket_name(entity),
        prefix: prefix,
        max_keys: max_keys
      })

      documents = response.contents.map do |object|
        # Skip metadata files
        next if object.key.end_with?('.metadata.json')

        {
          key: object.key,
          size: object.size,
          last_modified: object.last_modified,
          etag: object.etag,
          storage_class: object.storage_class
        }
      end.compact

      {
        documents: documents,
        count: documents.count,
        is_truncated: response.is_truncated,
        next_token: response.next_continuation_token
      }
    end

    private

    def credentials
      if ENV['AWS_ACCESS_KEY_ID'] && ENV['AWS_SECRET_ACCESS_KEY']
        Aws::Credentials.new(
          ENV['AWS_ACCESS_KEY_ID'],
          ENV['AWS_SECRET_ACCESS_KEY'],
          ENV['AWS_SESSION_TOKEN']
        )
      else
        Aws::InstanceProfileCredentials.new
      end
    end

    def ensure_knowledge_base(entity)
      return if entity.bedrock_knowledge_base_id.present?

      kb = create_knowledge_base(entity)
      entity.reload
    end

    def find_knowledge_base(name)
      response = @bedrock_agent_client.list_knowledge_bases({
        max_results: 100
      })

      response.knowledge_base_summaries.find { |kb| kb.name == name }
    rescue => e
      ::Rails.logger.error "Failed to list knowledge bases: #{e.message}"
      nil
    end

    def bucket_name(entity = nil)
      base_name = ENV.fetch('RAG_BUCKET', 'agent-marketing-rag-storage')
      return base_name unless entity

      # Use a prefix within the same bucket for multi-tenancy
      base_name
    end

    def ensure_s3_bucket(entity)
      bucket = bucket_name(entity)

      begin
        @s3_client.head_bucket(bucket: bucket)
      rescue Aws::S3::Errors::NotFound
        # Create bucket
        create_params = { bucket: bucket }
        region = ENV.fetch('AWS_REGION', 'us-east-1')
        if region != 'us-east-1'
          create_params[:create_bucket_configuration] = {
            location_constraint: region
          }
        end
        @s3_client.create_bucket(create_params)

        # Enable versioning
        @s3_client.put_bucket_versioning({
          bucket: bucket,
          versioning_configuration: {
            status: "Enabled"
          }
        })

        # Set lifecycle policy for cost optimization
        @s3_client.put_bucket_lifecycle_configuration({
          bucket: bucket,
          lifecycle_configuration: {
            rules: [
              {
                id: "TransitionToIntelligentTiering",
                status: "Enabled",
                transitions: [
                  {
                    days: 30,
                    storage_class: "INTELLIGENT_TIERING"
                  }
                ]
              },
              {
                id: "DeleteOldVersions",
                status: "Enabled",
                noncurrent_version_expiration: {
                  noncurrent_days: 90
                }
              }
            ]
          }
        })
      end

      bucket
    end

    def ensure_opensearch_collection(entity)
      collection_name = "entity-#{entity.id}-collection"

      # Note: OpenSearch Serverless collection creation is complex and requires
      # additional setup including security policies, data access policies, etc.
      # This is typically done through CloudFormation or Terraform

      # For now, return a placeholder ARN
      # In production, this would create or return existing collection ARN
      "arn:aws:opensearchserverless:#{ENV.fetch('AWS_REGION', 'us-east-1')}:#{account_id}:collection/#{collection_name}"
    end

    def knowledge_base_role_arn
      # This role needs to be created with proper permissions for Bedrock KB
      ENV.fetch('BEDROCK_KB_ROLE_ARN', "arn:aws:iam::#{account_id}:role/BedrockKnowledgeBaseRole")
    end

    def account_id
      ENV.fetch('AWS_ACCOUNT_ID', '123456789012')
    end

    def upload_document_to_s3(entity, file_path, metadata)
      file_name = File.basename(file_path)
      timestamp = Time.current.strftime('%Y%m%d%H%M%S')
      s3_key = "documents/#{entity.id}/#{timestamp}_#{file_name}"

      @s3_client.put_object({
        bucket: bucket_name(entity),
        key: s3_key,
        body: File.read(file_path),
        content_type: Marcel::MimeType.for(file_path),
        metadata: metadata.transform_keys(&:to_s).transform_values(&:to_s)
      })

      s3_key
    end

    def create_metadata_file(entity, s3_key, metadata)
      metadata_content = {
        document_id: SecureRandom.uuid,
        entity_id: entity.id,
        created_at: Time.current.iso8601,
        metadata: metadata
      }.to_json

      @s3_client.put_object({
        bucket: bucket_name(entity),
        key: "#{s3_key}.metadata.json",
        body: metadata_content,
        content_type: 'application/json'
      })
    end

    def create_data_source(knowledge_base_id, bucket_name, entity)
      @bedrock_agent_client.create_data_source({
        knowledge_base_id: knowledge_base_id,
        name: "entity-#{entity.id}-datasource",
        description: "S3 data source for entity #{entity.name}",
        data_source_configuration: {
          type: "S3",
          s3_configuration: {
            bucket_arn: "arn:aws:s3:::#{bucket_name}",
            inclusion_prefixes: ["documents/#{entity.id}/"]
          }
        },
        vector_ingestion_configuration: {
          chunking_configuration: {
            chunking_strategy: "FIXED_SIZE",
            fixed_size_chunking_configuration: {
              max_tokens: CHUNK_SIZE,
              overlap_percentage: (CHUNK_OVERLAP.to_f / CHUNK_SIZE * 100).to_i
            }
          }
        }
      })
    end

    def get_data_source_id(entity)
      data_sources = @bedrock_agent_client.list_data_sources({
        knowledge_base_id: entity.bedrock_knowledge_base_id,
        max_results: 10
      })

      data_sources.data_source_summaries.first&.data_source_id
    end

    def build_metadata_filter(filters)
      return nil unless filters&.any?

      # Build OpenSearch filter from provided filters
      # Example: { category: 'product', date_after: '2024-01-01' }
      filters
    end

    def build_prompt_template(system_prompt = nil)
      system_prompt || <<~PROMPT
        You are a helpful AI assistant with access to a knowledge base.
        Use the provided context to answer questions accurately.
        If the information is not in the context, say so clearly.

        Context:
        $search_results$

        Question: $query$

        Answer:
      PROMPT
    end

    def parse_citations(citations)
      return [] unless citations

      citations.map do |citation|
        {
          text: citation.generated_response_part.text,
          references: citation.retrieved_references.map do |ref|
            {
              content: ref.content.text,
              location: ref.location,
              metadata: ref.metadata
            }
          end
        }
      end
    end

    def track_retrieval_usage(entity, query, result_count)
      # Track for cost monitoring
      tracker = EntityCostTracker.new(entity)
      tracker.track_usage(
        category: :search,
        service: :bedrock_kb_retrieval,
        usage_type: :per_1k_queries,
        quantity: 0.001,  # 1 query = 0.001 of 1k queries
        metadata: {
          query_length: query.length,
          result_count: result_count
        }
      )
    end

    def track_generation_usage(entity, query, response)
      # Estimate token usage (rough approximation)
      input_tokens = (query.length / 4.0).ceil
      output_tokens = response.output.text ? (response.output.text.length / 4.0).ceil : 0

      tracker = EntityCostTracker.new(entity)
      tracker.track_scout_conversation(
        message_count: 1,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        model: 'qwen3-next-80b'
      )
    end
  end
end