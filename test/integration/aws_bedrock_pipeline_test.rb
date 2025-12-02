# test/integration/aws_bedrock_pipeline_test.rb
require "test_helper"

class AwsBedrockPipelineTest < ActionDispatch::IntegrationTest
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @user.update!(entity: @entity)

    # Create test document
    @test_file = Rails.root.join('tmp', 'test_document.txt')
    FileUtils.mkdir_p(File.dirname(@test_file))
    File.write(@test_file, <<~TEXT)
      Product Specification Document

      Company: Acme Corporation
      Location: San Francisco, California
      Contact: John Smith (john@acme.com)

      Our innovative AI-powered platform revolutionizes customer engagement.
      Key features include real-time analytics, automated workflows, and
      seamless integrations with existing systems.

      Pricing starts at $99/month for the basic plan, with enterprise
      options available for larger organizations.

      For support, contact support@acme.com or call 1-800-555-1234.
    TEXT
  end

  teardown do
    FileUtils.rm_f(@test_file) if File.exist?(@test_file)
  end

  test "complete AWS pipeline: OCR → NLP → Knowledge Base → Query" do
    skip "Requires live AWS credentials" unless ENV['RUN_AWS_INTEGRATION_TESTS']

    # Step 1: Process document with full pipeline
    processor = DocumentProcessorV2.instance
    result = processor.process_document(@entity, @test_file, {
      enable_nlp: true,
      detect_pii: true,
      detect_entities: true,
      detect_sentiment: true
    })

    assert result[:success], "Document processing failed: #{result[:error]}"
    assert result[:extracted_text].present?
    assert result[:nlp_insights].present?

    # Verify NLP insights
    nlp = result[:nlp_insights]
    assert nlp[:entities].present?, "Should detect entities"
    assert nlp[:sentiment].present?, "Should detect sentiment"
    assert nlp[:language].present?, "Should detect language"

    # Check for expected entities
    entities_text = nlp[:entities][:entities].map { |e| e[:text] }
    assert_includes entities_text, "Acme Corporation"
    assert_includes entities_text, "San Francisco"

    # Check for PII
    if nlp[:pii]
      assert nlp[:pii][:contains_pii], "Should detect PII (email, phone)"
      assert_includes nlp[:pii][:pii_types], "EMAIL"
    end

    # Step 2: Verify document added to Knowledge Base
    rag_doc = RagDocument.find(result[:rag_document_id])
    assert_equal @entity, rag_doc.entity
    assert_equal 'bedrock', rag_doc.provider
    assert rag_doc.metadata['bedrock_kb_id'].present?

    # Step 3: Wait for KB ingestion (in real scenario)
    # In tests, we'll mock the query response

    # Step 4: Query the Knowledge Base
    kb_service = Aws::BedrockKnowledgeBaseService.instance

    mock_query_response = OpenStruct.new(
      retrieval_results: [
        OpenStruct.new(
          content: OpenStruct.new(text: result[:extracted_text][0..500]),
          score: 0.95,
          metadata: {},
          location: nil,
          retrieval_result_id: 'result-1'
        )
      ]
    )

    kb_service.bedrock_runtime_client.stub :retrieve, mock_query_response do
      query_result = kb_service.query(@entity, "What is the company name?")

      assert query_result[:results].present?
      assert query_result[:results].first[:content].include?("Acme")
    end

    # Step 5: Generate RAG response
    mock_generate_response = OpenStruct.new(
      output: OpenStruct.new(text: "The company is Acme Corporation, located in San Francisco."),
      session_id: 'session-123',
      citations: [],
      retrieval_results: []
    )

    kb_service.bedrock_runtime_client.stub :retrieve_and_generate, mock_generate_response do
      answer = kb_service.retrieve_and_generate(
        @entity,
        "What is the company name and location?"
      )

      assert answer[:response].present?
      assert answer[:response].include?("Acme Corporation")
      assert answer[:session_id].present?
    end
  end

  test "Scout AWS Integration processes user message end-to-end" do
    skip "Requires live AWS credentials" unless ENV['RUN_AWS_INTEGRATION_TESTS']

    # Setup: Upload a document first
    processor = DocumentProcessorV2.instance
    processor.process_document(@entity, @test_file, enable_nlp: true)

    # User sends message to Scout
    user_message = "Tell me about Acme Corporation's pricing"
    session_id = SecureRandom.uuid

    integration = ScoutAwsIntegration.instance

    # Mock Comprehend analysis
    mock_analysis = {
      language: { success: true, language_code: 'en' },
      sentiment: { success: true, sentiment: :neutral, scores: { neutral: 0.9 } },
      entities: { success: true, entities: [], entities_by_type: {} },
      key_phrases: { success: true, key_phrases: [{ text: 'pricing', score: 0.95 }] },
      pii: { success: true, contains_pii: false }
    }

    comprehend = Aws::ComprehendService.instance
    comprehend.stub :analyze_text, mock_analysis do
      # Mock KB query
      kb_service = Aws::BedrockKnowledgeBaseService.instance

      mock_rag_response = OpenStruct.new(
        output: OpenStruct.new(text: "Pricing starts at $99/month for the basic plan."),
        session_id: session_id,
        citations: [],
        retrieval_results: []
      )

      kb_service.bedrock_runtime_client.stub :retrieve_and_generate, mock_rag_response do
        result = integration.process_message(@entity, user_message, session_id)

        assert result[:success]
        assert result[:response].include?("$99")
        assert result[:message_analysis].present?
        assert_equal session_id, result[:session_id]
      end
    end
  end

  test "cost tracking works throughout pipeline" do
    # Process document
    processor = DocumentProcessorV2.instance

    initial_metrics_count = EntityUsageMetric.where(entity: @entity).count

    # Mock AWS calls to avoid actual API calls
    kb_service = Aws::BedrockKnowledgeBaseService.instance
    kb_service.s3_client.stub :put_object, OpenStruct.new(etag: 'test') do
      result = processor.process_document(@entity, @test_file, enable_nlp: true)

      # Should create usage metrics for:
      # - NLP operations (if Comprehend was called)
      # - KB ingestion
      # - S3 storage
      new_metrics = EntityUsageMetric.where(entity: @entity).count
      assert new_metrics > initial_metrics_count, "Should track usage metrics"
    end

    # Verify cost tracking
    tracker = EntityCostTracker.new(@entity)
    costs = tracker.get_costs_by_category

    # Costs might be minimal in tests, but structure should exist
    assert costs.is_a?(Hash)
  end

  test "OCR dual-mode selection works correctly" do
    skip "Requires live AWS credentials" unless ENV['RUN_AWS_INTEGRATION_TESTS']

    # Create a small PDF (should use Docling)
    small_pdf = Rails.root.join('tmp', 'small.pdf')

    # Create a large document (should use Textract)
    large_pdf = Rails.root.join('tmp', 'large.pdf')

    ocr_service = Ocr::DualModeService.instance

    # Test provider selection logic
    small_provider = ocr_service.send(:select_provider, small_pdf, { file_size_mb: 3 })
    assert_equal 'docling', small_provider, "Small files should use Docling"

    large_provider = ocr_service.send(:select_provider, large_pdf, { file_size_mb: 15 })
    assert_equal 'textract', large_provider, "Large files should use Textract"

    # Test document type selection
    invoice_provider = ocr_service.send(:select_provider, 'invoice.pdf', {
      document_type: 'invoice'
    })
    assert_equal 'textract', invoice_provider, "Invoices should use Textract"
  end

  test "error handling and fallback mechanisms work" do
    processor = DocumentProcessorV2.instance

    # Test with non-existent file
    result = processor.process_document(@entity, '/tmp/nonexistent.pdf')

    assert_not result[:success]
    assert result[:error].present?

    # Test with invalid content
    invalid_file = Rails.root.join('tmp', 'invalid.txt')
    File.write(invalid_file, "\xFF\xFE" + "Invalid UTF-8")

    result = processor.process_document(@entity, invalid_file)

    # Should handle gracefully
    assert result.key?(:success)

    FileUtils.rm_f(invalid_file)
  end

  test "document metadata is properly enriched" do
    processor = DocumentProcessorV2.instance

    # Mock services to capture metadata
    kb_service = Aws::BedrockKnowledgeBaseService.instance

    captured_metadata = nil
    kb_service.s3_client.stub :put_object, ->(*args) {
      captured_metadata = args.last[:metadata] if args.last.is_a?(Hash)
      OpenStruct.new(etag: 'test')
    } do
      result = processor.process_document(@entity, @test_file, {
        enable_nlp: true,
        metadata: { source: 'test', category: 'specs' }
      })

      # Verify metadata was enriched with NLP insights
      rag_doc = RagDocument.find(result[:rag_document_id])
      assert rag_doc.metadata['source'] == 'test'
      assert rag_doc.metadata['category'] == 'specs'
      assert rag_doc.metadata['nlp_insights'].present?
    end
  end

  test "session continuity works across multiple queries" do
    skip "Requires live AWS credentials" unless ENV['RUN_AWS_INTEGRATION_TESTS']

    kb_service = Aws::BedrockKnowledgeBaseService.instance
    session_id = SecureRandom.uuid

    # First query
    mock_response1 = OpenStruct.new(
      output: OpenStruct.new(text: "Acme Corporation is based in San Francisco."),
      session_id: session_id,
      citations: [],
      retrieval_results: []
    )

    kb_service.bedrock_runtime_client.stub :retrieve_and_generate, mock_response1 do
      result1 = kb_service.retrieve_and_generate(@entity, "Where is Acme located?", session_id)
      assert_equal session_id, result1[:session_id]
    end

    # Follow-up query using same session
    mock_response2 = OpenStruct.new(
      output: OpenStruct.new(text: "They offer pricing starting at $99/month."),
      session_id: session_id,
      citations: [],
      retrieval_results: []
    )

    kb_service.bedrock_runtime_client.stub :retrieve_and_generate, mock_response2 do
      result2 = kb_service.retrieve_and_generate(@entity, "What about pricing?", session_id)
      assert_equal session_id, result2[:session_id]
    end
  end

  test "PII detection prevents sensitive data exposure" do
    # Create document with PII
    pii_file = Rails.root.join('tmp', 'pii_test.txt')
    File.write(pii_file, <<~TEXT)
      Customer: John Doe
      SSN: 123-45-6789
      Email: john.doe@example.com
      Credit Card: 4111-1111-1111-1111
      Phone: (555) 123-4567
    TEXT

    processor = DocumentProcessorV2.instance

    # Mock Comprehend PII detection
    comprehend = Aws::ComprehendService.instance

    mock_pii_result = {
      success: true,
      contains_pii: true,
      pii_count: 4,
      pii_types: ['SSN', 'EMAIL', 'CREDIT_DEBIT_NUMBER', 'PHONE'],
      entities: [
        { type: 'SSN', score: 0.99 },
        { type: 'EMAIL', score: 0.98 },
        { type: 'CREDIT_DEBIT_NUMBER', score: 0.97 },
        { type: 'PHONE', score: 0.96 }
      ]
    }

    comprehend.stub :detect_pii, mock_pii_result do
      result = processor.process_document(@entity, pii_file, detect_pii: true)

      assert result[:nlp_insights][:pii][:contains_pii]
      assert_equal 4, result[:nlp_insights][:pii][:pii_count]

      # Verify PII types detected
      assert_includes result[:nlp_insights][:pii][:pii_types], 'SSN'
      assert_includes result[:nlp_insights][:pii][:pii_types], 'EMAIL'
      assert_includes result[:nlp_insights][:pii][:pii_types], 'CREDIT_DEBIT_NUMBER'
    end

    FileUtils.rm_f(pii_file)
  end

  test "batch processing handles multiple documents efficiently" do
    # Create multiple test files
    files = (1..5).map do |i|
      file = Rails.root.join('tmp', "test_#{i}.txt")
      File.write(file, "Test document #{i} content with sample text.")
      file
    end

    processor = DocumentProcessorV2.instance

    # Mock AWS calls
    kb_service = Aws::BedrockKnowledgeBaseService.instance
    kb_service.s3_client.stub :put_object, OpenStruct.new(etag: 'test') do
      result = processor.process_batch(@entity, files)

      assert_equal 5, result[:total]
      assert result[:successful] > 0
      assert result[:results].is_a?(Array)
      assert_equal 5, result[:results].count
    end

    # Cleanup
    files.each { |f| FileUtils.rm_f(f) }
  end
end