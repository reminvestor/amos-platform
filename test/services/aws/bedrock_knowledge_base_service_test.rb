# test/services/aws/bedrock_knowledge_base_service_test.rb
require "test_helper"

module Aws
  class BedrockKnowledgeBaseServiceTest < ActiveSupport::TestCase
    setup do
      @service = BedrockKnowledgeBaseService.instance
      @entity = entities(:one)
      @entity.update!(
        bedrock_knowledge_base_id: 'test-kb-id-123',
        bedrock_kb_status: 'ACTIVE'
      )
    end

    test "singleton pattern works" do
      assert_same @service, BedrockKnowledgeBaseService.instance
    end

    test "creates knowledge base for entity" do
      entity = entities(:two)
      entity.update!(bedrock_knowledge_base_id: nil)

      # Mock AWS client responses
      mock_kb_response = OpenStruct.new(
        knowledge_base: OpenStruct.new(
          knowledge_base_id: 'new-kb-123',
          name: "entity-#{entity.id}-kb",
          arn: 'arn:aws:bedrock:us-east-1:123:kb/new-kb-123'
        )
      )

      # Stub S3 and OpenSearch operations to prevent actual AWS calls
      @service.stub :ensure_s3_bucket, 'test-bucket' do
        @service.stub :ensure_opensearch_collection, 'arn:aws:aoss:us-east-1:123:collection/test' do
          @service.bedrock_agent_client.stub :create_knowledge_base, mock_kb_response do
            @service.bedrock_agent_client.stub :create_data_source, OpenStruct.new(data_source: OpenStruct.new(data_source_id: 'ds-123')) do
              @service.bedrock_agent_client.stub :list_data_sources, OpenStruct.new(data_source_summaries: [OpenStruct.new(data_source_id: 'ds-123')]) do
                @service.bedrock_agent_client.stub :start_ingestion_job, OpenStruct.new(ingestion_job: OpenStruct.new(ingestion_job_id: 'job-123')) do
                  kb = @service.create_knowledge_base(entity)

                  assert_not_nil kb
                  assert_equal 'new-kb-123', kb.knowledge_base_id

                  entity.reload
                  assert_equal 'new-kb-123', entity.bedrock_knowledge_base_id
                end
              end
            end
          end
        end
      end
    end

    test "finds existing knowledge base" do
      mock_list_response = OpenStruct.new(
        knowledge_base_summaries: [
          OpenStruct.new(
            name: "entity-#{@entity.id}-kb",
            knowledge_base_id: 'existing-kb-123'
          )
        ]
      )

      @service.bedrock_agent_client.stub :list_knowledge_bases, mock_list_response do
        kb = @service.send(:find_knowledge_base, "entity-#{@entity.id}-kb")
        assert_not_nil kb
        assert_equal 'existing-kb-123', kb.knowledge_base_id
      end
    end

    test "adds document to knowledge base" do
      file_path = ::Rails.root.join('test', 'fixtures', 'files', 'sample.txt')
      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, "Test content for knowledge base")

      metadata = {
        category: 'test',
        source: 'unit_test'
      }

      # Mock S3 upload and ingestion job
      @service.s3_client.stub :put_object, OpenStruct.new(etag: 'test-etag') do
        @service.bedrock_agent_client.stub :list_data_sources, OpenStruct.new(data_source_summaries: [OpenStruct.new(data_source_id: 'ds-123')]) do
          @service.bedrock_agent_client.stub :start_ingestion_job, OpenStruct.new(ingestion_job: OpenStruct.new(ingestion_job_id: 'job-123', status: 'STARTING')) do
            result = @service.add_document(@entity, file_path, metadata)

            assert result[:success]
            assert result[:s3_key].present?
            assert result[:s3_key].starts_with?("documents/#{@entity.id}/")
          end
        end
      end

      FileUtils.rm_f(file_path)
    end

    test "queries knowledge base" do
      query = "What is the test about?"

      mock_response = OpenStruct.new(
        retrieval_results: [
          OpenStruct.new(
            content: OpenStruct.new(text: "This is test content"),
            score: 0.95,
            metadata: {},
            location: nil,
            retrieval_result_id: 'result-1'
          ),
          OpenStruct.new(
            content: OpenStruct.new(text: "More test content"),
            score: 0.87,
            metadata: {},
            location: nil,
            retrieval_result_id: 'result-2'
          )
        ]
      )

      @service.bedrock_runtime_client.stub :retrieve, mock_response do
        result = @service.query(@entity, query, max_results: 5)

        assert_equal query, result[:query]
        assert_equal 2, result[:result_count]
        assert_equal "This is test content", result[:results].first[:content]
        assert_equal 0.95, result[:results].first[:score]
      end
    end

    test "retrieve and generate with RAG" do
      query = "Summarize the documents"

      mock_response = OpenStruct.new(
        output: OpenStruct.new(text: "This is a generated summary"),
        session_id: 'session-123',
        citations: [],
        retrieval_results: [
          OpenStruct.new(
            content: OpenStruct.new(text: "Retrieved content"),
            score: 0.9,
            metadata: {}
          )
        ]
      )

      @service.bedrock_runtime_client.stub :retrieve_and_generate, mock_response do
        result = @service.retrieve_and_generate(@entity, query)

        assert_equal "This is a generated summary", result[:response]
        assert_equal 'session-123', result[:session_id]
        assert_equal 1, result[:retrieval_results].count
      end
    end

    test "starts ingestion job" do
      mock_list_ds = OpenStruct.new(
        data_source_summaries: [
          OpenStruct.new(data_source_id: 'ds-123')
        ]
      )

      mock_job = OpenStruct.new(
        ingestion_job: OpenStruct.new(
          ingestion_job_id: 'job-123',
          status: 'STARTING'
        )
      )

      @service.bedrock_agent_client.stub :list_data_sources, mock_list_ds do
        @service.bedrock_agent_client.stub :start_ingestion_job, mock_job do
          job = @service.start_ingestion_job(@entity.bedrock_knowledge_base_id, @entity)

          assert_equal 'job-123', job.ingestion_job_id
          assert_equal 'STARTING', job.status

          @entity.reload
          assert_equal 'job-123', @entity.bedrock_last_ingestion_job_id
        end
      end
    end

    test "checks ingestion status" do
      @entity.update!(bedrock_last_ingestion_job_id: 'job-123')

      mock_response = OpenStruct.new(
        ingestion_job: OpenStruct.new(
          ingestion_job_id: 'job-123',
          status: 'COMPLETE',
          started_at: 1.hour.ago,
          updated_at: 30.minutes.ago,
          statistics: OpenStruct.new(
            number_of_documents_scanned: 10,
            number_of_documents_indexed: 10,
            number_of_documents_failed: 0,
            number_of_documents_deleted: 0
          ),
          failure_reasons: []
        )
      )

      @service.bedrock_agent_client.stub :get_ingestion_job, mock_response do
        @service.bedrock_agent_client.stub :list_data_sources, OpenStruct.new(data_source_summaries: [OpenStruct.new(data_source_id: 'ds-123')]) do
          status = @service.check_ingestion_status(@entity)

          assert_equal 'job-123', status[:job_id]
          assert_equal 'COMPLETE', status[:status]
          assert_equal 10, status[:statistics][:documents_indexed]
          assert_equal 0, status[:statistics][:documents_failed]
        end
      end
    end

    test "deletes document from knowledge base" do
      doc = rag_documents(:one)
      # Set metadata with S3 key
      doc.update!(metadata: { 's3_key' => 'documents/test/file.pdf' })

      @service.s3_client.stub :delete_object, OpenStruct.new(delete_marker: true) do
        @service.bedrock_agent_client.stub :list_data_sources, OpenStruct.new(data_source_summaries: []) do
          # Need to stub entity.rag_documents association
          @entity.stub :rag_documents, RagDocument.where(id: doc.id) do
            result = @service.delete_document(@entity, doc.id)

            assert result[:success]

            doc.reload
            assert_equal 'deleted', doc.processing_status
            assert_not_nil doc.deleted_at
          end
        end
      end
    end

    test "lists documents in knowledge base" do
      mock_response = OpenStruct.new(
        contents: [
          OpenStruct.new(
            key: 'documents/1/file1.pdf',
            size: 1024,
            last_modified: Time.current,
            etag: 'etag1',
            storage_class: 'STANDARD'
          ),
          OpenStruct.new(
            key: 'documents/1/file2.txt',
            size: 512,
            last_modified: Time.current,
            etag: 'etag2',
            storage_class: 'INTELLIGENT_TIERING'
          ),
          OpenStruct.new(
            key: 'documents/1/file.metadata.json',  # Should be skipped
            size: 256,
            last_modified: Time.current,
            etag: 'etag3',
            storage_class: 'STANDARD'
          )
        ],
        is_truncated: false,
        next_continuation_token: nil
      )

      @service.s3_client.stub :list_objects_v2, mock_response do
        result = @service.list_documents(@entity)

        assert_equal 2, result[:count]  # Metadata file excluded
        assert_equal 'documents/1/file1.pdf', result[:documents].first[:key]
        assert_equal 1024, result[:documents].first[:size]
        assert_equal false, result[:is_truncated]
      end
    end

    test "handles query errors gracefully" do
      @service.bedrock_runtime_client.stub :retrieve, ->(*args) { raise StandardError.new("API Error") } do
        result = @service.query(@entity, "test query")

        assert_equal [], result[:results]
        assert result[:error].present?
        assert_includes result[:error], "API Error"
      end
    end

    test "ensures knowledge base exists before operations" do
      entity = entities(:two)
      entity.update!(bedrock_knowledge_base_id: nil)

      # Mock KB creation and S3 bucket operations
      mock_kb = OpenStruct.new(
        knowledge_base: OpenStruct.new(
          knowledge_base_id: 'new-kb-123',
          arn: 'arn:aws:bedrock:us-east-1:123:kb/new-kb-123'
        )
      )

      # Stub ensure_s3_bucket to prevent actual S3 API calls
      @service.stub :ensure_s3_bucket, 'test-bucket' do
        @service.stub :ensure_opensearch_collection, 'arn:aws:aoss:us-east-1:123:collection/test' do
          @service.bedrock_agent_client.stub :create_knowledge_base, mock_kb do
            @service.bedrock_agent_client.stub :create_data_source, OpenStruct.new(data_source: OpenStruct.new(data_source_id: 'ds-123')) do
              @service.bedrock_agent_client.stub :start_ingestion_job, OpenStruct.new(ingestion_job: OpenStruct.new(ingestion_job_id: 'job-123')) do
                @service.send(:ensure_knowledge_base, entity)

                entity.reload
                assert_equal 'new-kb-123', entity.bedrock_knowledge_base_id
              end
            end
          end
        end
      end
    end

    test "tracks retrieval usage for cost monitoring" do
      query = "test query"
      results_count = 3

      assert_difference 'EntityUsageMetric.count', 1 do
        @service.send(:track_retrieval_usage, @entity, query, results_count)
      end

      metric = EntityUsageMetric.last
      assert_equal @entity, metric.entity
      assert_equal 'search', metric.category
      assert_equal 'bedrock_kb_retrieval', metric.service
    end
  end
end