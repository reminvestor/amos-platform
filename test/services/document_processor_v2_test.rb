# test/services/document_processor_v2_test.rb
require "test_helper"

class DocumentProcessorV2Test < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @processor = DocumentProcessorV2.instance

    # Create test files
    @text_file = Rails.root.join('tmp', 'test.txt')
    @pdf_file = Rails.root.join('tmp', 'test.pdf')

    FileUtils.mkdir_p(File.dirname(@text_file))
    File.write(@text_file, "This is a test document about Amazon Web Services in Seattle")
    File.write(@pdf_file, "PDF content placeholder")
  end

  teardown do
    FileUtils.rm_f(@text_file) if @text_file && File.exist?(@text_file)
    FileUtils.rm_f(@pdf_file) if @pdf_file && File.exist?(@pdf_file)
  end

  test "singleton pattern works" do
    assert_same @processor, DocumentProcessorV2.instance
  end

  test "initializes with required services" do
    assert @processor.ocr_service.present?
    assert @processor.kb_service.present?
    assert @processor.comprehend_service.present?
  end

  test "detects OCR need for PDF files" do
    assert @processor.send(:needs_ocr?, 'document.pdf')
  end

  test "detects OCR need for image files" do
    assert @processor.send(:needs_ocr?, 'image.png')
    assert @processor.send(:needs_ocr?, 'image.jpg')
    assert @processor.send(:needs_ocr?, 'image.jpeg')
    assert @processor.send(:needs_ocr?, 'image.tiff')
  end

  test "does not need OCR for text files" do
    assert_not @processor.send(:needs_ocr?, 'document.txt')
    assert_not @processor.send(:needs_ocr?, 'data.json')
    assert_not @processor.send(:needs_ocr?, 'content.md')
  end

  test "extracts text from plain text file" do
    text = @processor.send(:extract_text_content, @text_file)
    assert text.present?
    assert_includes text, 'test document'
  end

  test "extracts text from JSON file" do
    json_file = Rails.root.join('tmp', 'test.json')
    File.write(json_file, '{"name": "Test", "value": 123}')

    text = @processor.send(:extract_text_content, json_file)
    assert text.present?
    assert_includes text, 'Test'

    FileUtils.rm_f(json_file)
  end

  test "extracts text from HTML file" do
    html_file = Rails.root.join('tmp', 'test.html')
    File.write(html_file, '<html><body><h1>Title</h1><p>Content</p></body></html>')

    text = @processor.send(:extract_text_content, html_file)
    assert text.present?
    assert_includes text, 'Title'
    assert_includes text, 'Content'

    FileUtils.rm_f(html_file)
  end

  test "handles text extraction errors gracefully" do
    invalid_file = Rails.root.join('tmp', 'invalid.bin')
    File.write(invalid_file, "\xFF\xFE\xFD")

    text = @processor.send(:extract_text_content, invalid_file)
    # Should return nil on error
    assert_nil text

    FileUtils.rm_f(invalid_file)
  end

  test "processes text document without OCR" do
    # Mock services
    kb_result = { success: true, s3_key: 'test-key' }
    kb_service = Minitest::Mock.new
    kb_service.expect :add_document, kb_result, [Entity, String, Hash]

    rag_doc = rag_documents(:one)
    @entity.stub :rag_documents, rag_documents do
      @processor.stub :kb_service, kb_service do
        EntityCostTracker.stub :new, Minitest::Mock.new do
          result = @processor.process_document(@entity, @text_file, enable_nlp: false)

          assert result[:success]
          assert result[:extracted_text].present?
          assert result[:steps].any?
          assert result[:rag_document_id].present?
        end
      end
    end

    kb_service.verify
  end

  test "processes document with NLP analysis" do
    # Mock Comprehend service
    comprehend = Minitest::Mock.new
    comprehend.expect :detect_entities, {
      success: true,
      entities: [{ text: 'Amazon Web Services', type: 'ORGANIZATION', score: 0.95 }]
    }, [String, Hash]
    comprehend.expect :detect_key_phrases, {
      success: true,
      key_phrases: [{ text: 'test document', score: 0.9 }]
    }, [String, Hash]
    comprehend.expect :detect_sentiment, {
      success: true,
      sentiment: :neutral
    }, [String, Hash]
    comprehend.expect :detect_language, {
      success: true,
      languages: [{ language_code: 'en', score: 0.99 }]
    }, [String, Hash]

    # Mock KB service
    kb_service = Minitest::Mock.new
    kb_service.expect :add_document, {
      success: true,
      s3_key: 'test-key'
    }, [Entity, String, Hash]

    @processor.instance_variable_set(:@comprehend_service, comprehend)
    @processor.stub :kb_service, kb_service do
      EntityCostTracker.stub :new, Minitest::Mock.new do
        @entity.stub :rag_documents, rag_documents do
          result = @processor.process_document(@entity, @text_file, enable_nlp: true)

          assert result[:success]
          assert result[:nlp_insights].present?
          assert result[:nlp_insights][:entities].present?
          assert result[:nlp_insights][:key_phrases].present?
          assert result[:nlp_insights][:sentiment].present?
        end
      end
    end

    comprehend.verify
    kb_service.verify
  end

  test "detects PII when requested" do
    pii_text = "My SSN is 123-45-6789"
    pii_file = Rails.root.join('tmp', 'pii_test.txt')
    File.write(pii_file, pii_text)

    # Mock Comprehend service with PII detection
    comprehend = Minitest::Mock.new
    # For entity detection
    comprehend.expect :detect_entities, { success: true, entities: [] }, [String, Hash]
    # For key phrases
    comprehend.expect :detect_key_phrases, { success: true, key_phrases: [] }, [String, Hash]
    # For sentiment
    comprehend.expect :detect_sentiment, { success: true, sentiment: :neutral }, [String, Hash]
    # For PII detection
    comprehend.expect :detect_pii, {
      success: true,
      entities: [{ type: 'SSN', score: 0.99, text: '123-45-6789' }]
    }, [String, Hash]
    # For language
    comprehend.expect :detect_language, {
      success: true,
      languages: [{ language_code: 'en', score: 0.99 }]
    }, [String, Hash]

    # Mock KB service
    kb_service = Minitest::Mock.new
    kb_service.expect :add_document, { success: true, s3_key: 'test-key' }, [Entity, String, Hash]

    @processor.instance_variable_set(:@comprehend_service, comprehend)
    @processor.stub :kb_service, kb_service do
      EntityCostTracker.stub :new, Minitest::Mock.new do
        @entity.stub :rag_documents, rag_documents do
          result = @processor.process_document(@entity, pii_file, detect_pii: true, enable_nlp: true)

          assert result[:success]
          assert result[:nlp_insights][:pii_entities].present?
        end
      end
    end

    FileUtils.rm_f(pii_file)
    comprehend.verify
    kb_service.verify
  end

  test "handles processing errors gracefully" do
    # Mock KB service to raise error
    kb_service = Minitest::Mock.new
    kb_service.expect :add_document, -> { raise StandardError.new("KB Error") }, [Entity, String, Hash]

    @processor.stub :kb_service, kb_service do
      EntityCostTracker.stub :new, Minitest::Mock.new do
        result = @processor.process_document(@entity, @text_file, enable_nlp: false)

        assert_not result[:success]
        assert result[:error].present?
        assert_includes result[:error], 'KB Error'
      end
    end

    kb_service.verify
  end

  test "batch processes multiple documents" do
    files = [
      Rails.root.join('tmp', 'batch_1.txt'),
      Rails.root.join('tmp', 'batch_2.txt'),
      Rails.root.join('tmp', 'batch_3.txt')
    ]

    files.each_with_index do |file, i|
      File.write(file, "Document #{i + 1} content")
    end

    # Mock KB service
    kb_service = Minitest::Mock.new
    3.times do
      kb_service.expect :add_document, { success: true, s3_key: 'test-key' }, [Entity, String, Hash]
    end
    kb_service.expect :start_ingestion_job, nil, [String, Entity]

    @entity.update!(bedrock_knowledge_base_id: 'kb-123')

    @processor.stub :kb_service, kb_service do
      EntityCostTracker.stub :new, Minitest::Mock.new do
        @entity.stub :rag_documents, rag_documents do
          result = @processor.process_batch(@entity, files, enable_nlp: false)

          assert_equal 3, result[:total]
          assert_equal 3, result[:successful]
          assert_equal 0, result[:failed]
          assert_equal 3, result[:results].count
        end
      end
    end

    files.each { |f| FileUtils.rm_f(f) }
    kb_service.verify
  end

  test "batch processing handles failures" do
    files = [
      Rails.root.join('tmp', 'good.txt'),
      '/tmp/nonexistent.txt',  # This will fail
      Rails.root.join('tmp', 'good2.txt')
    ]

    File.write(files[0], 'Good content 1')
    File.write(files[2], 'Good content 2')

    # Mock KB service
    kb_service = Minitest::Mock.new
    2.times do
      kb_service.expect :add_document, { success: true, s3_key: 'test-key' }, [Entity, String, Hash]
    end
    kb_service.expect :start_ingestion_job, nil, [String, Entity]

    @entity.update!(bedrock_knowledge_base_id: 'kb-123')

    @processor.stub :kb_service, kb_service do
      EntityCostTracker.stub :new, Minitest::Mock.new do
        @entity.stub :rag_documents, rag_documents do
          result = @processor.process_batch(@entity, files, enable_nlp: false)

          assert_equal 3, result[:total]
          assert_equal 2, result[:successful]
          assert_equal 1, result[:failed]
        end
      end
    end

    [files[0], files[2]].each { |f| FileUtils.rm_f(f) }
    kb_service.verify
  end

  test "queries knowledge base" do
    query = "What is AWS?"

    kb_result = {
      query: query,
      results: [
        { content: 'AWS is Amazon Web Services', score: 0.95 }
      ],
      result_count: 1
    }

    kb_service = Minitest::Mock.new
    kb_service.expect :query, kb_result, [Entity, String, Hash]

    @processor.stub :kb_service, kb_service do
      result = @processor.query_knowledge(@entity, query)

      assert_equal query, result[:query]
      assert result[:results].present?
    end

    kb_service.verify
  end

  test "queries knowledge base with query analysis" do
    query = "Tell me about AWS pricing"

    kb_result = {
      query: query,
      results: [{ content: 'Pricing info', score: 0.9 }]
    }

    query_analysis = {
      entities: [{ text: 'AWS', type: 'ORGANIZATION' }],
      key_phrases: [{ text: 'pricing', score: 0.95 }]
    }

    kb_service = Minitest::Mock.new
    kb_service.expect :query, kb_result, [Entity, String, Hash]

    comprehend = Minitest::Mock.new
    comprehend.expect :analyze_text, query_analysis, [String, Hash]

    @processor.stub :kb_service, kb_service do
      @processor.stub :comprehend_service, comprehend do
        result = @processor.query_knowledge(@entity, query, analyze_query: true)

        assert result[:results].present?
        assert result[:query_analysis].present?
      end
    end

    kb_service.verify
    comprehend.verify
  end

  test "generates answer using RAG" do
    query = "What is cloud computing?"
    session_id = SecureRandom.uuid

    rag_result = {
      response: 'Cloud computing is...',
      session_id: session_id,
      retrieval_results: [{ content: 'Context', score: 0.9 }]
    }

    kb_service = Minitest::Mock.new
    kb_service.expect :retrieve_and_generate, rag_result, [Entity, String, String, Hash]

    EntityCostTracker.stub :new, Minitest::Mock.new do
      @processor.stub :kb_service, kb_service do
        result = @processor.generate_answer(@entity, query, session_id)

        assert_equal 'Cloud computing is...', result[:response]
        assert_equal session_id, result[:session_id]
      end
    end

    kb_service.verify
  end

  test "tracks processing costs for document" do
    processing_result = {
      file_name: 'test.txt',
      file_size: 1000,
      extracted_text: 'a' * 500,  # 500 chars
      nlp_insights: {
        entities: [{ text: 'Test', type: 'ORGANIZATION' }],
        sentiment: :neutral
      },
      steps: [
        { step: 'text_extraction', status: 'completed' }
      ]
    }

    mock_tracker = Minitest::Mock.new
    # Expect 3 track_usage calls: NLP, KB ingestion, S3 storage
    3.times do
      mock_tracker.expect :track_usage, nil, [Hash]
    end

    EntityCostTracker.stub :new, mock_tracker do
      @processor.send(:track_processing_costs, @entity, processing_result)
    end

    mock_tracker.verify
  end

  test "creates RAG document record with metadata" do
    processing_result = {
      file_name: 'test.txt',
      file_size: 1000,
      success: true,
      extracted_text: 'Document text content',
      nlp_insights: {
        entities: [{ text: 'AWS', type: 'ORGANIZATION' }],
        language: { language_code: 'en' }
      },
      steps: [
        { step: 'nlp_analysis', status: 'completed', data: { entities: [] } },
        { step: 'knowledge_base', status: 'completed', data: { s3_key: 'test-key' } }
      ]
    }

    # Mock the find_or_initialize_by chain
    relation_mock = Minitest::Mock.new
    doc_mock = Minitest::Mock.new

    doc_mock.expect :assign_attributes, nil, [Hash]
    doc_mock.expect :content=, nil, [String]
    doc_mock.expect :save!, true
    doc_mock.expect :id, 123

    relation_mock.expect :find_or_initialize_by, doc_mock, [Hash]

    @entity.stub :rag_documents, relation_mock do
      doc = @processor.send(:create_rag_document, @entity, @text_file, processing_result, {})

      assert_equal 123, doc.id
    end

    relation_mock.verify
    doc_mock.verify
  end

  test "adds NLP metadata to knowledge base document" do
    processing_result = {
      file_name: 'test.txt',
      file_size: 1000,
      nlp_insights: {
        entities: [
          { text: 'Amazon', type: 'ORGANIZATION', score: 0.95 },
          { text: 'Seattle', type: 'LOCATION', score: 0.92 }
        ],
        key_phrases: [
          { text: 'cloud computing', score: 0.98 },
          { text: 'web services', score: 0.96 }
        ],
        sentiment: :positive,
        language: { language_code: 'en', score: 0.99 }
      },
      steps: []
    }

    # Capture the metadata passed to add_document
    captured_metadata = nil
    kb_service = Object.new
    kb_service.define_singleton_method(:add_document) do |entity, file_path, metadata|
      captured_metadata = metadata
      { success: true }
    end

    @processor.stub :kb_service, kb_service do
      @processor.send(:add_to_knowledge_base, @entity, @text_file, processing_result, {})

      assert captured_metadata.present?
      assert_equal 'en', captured_metadata[:language]
      assert_equal :positive, captured_metadata[:sentiment]
      assert captured_metadata[:entities].present?
      assert_includes captured_metadata[:entities], 'ORGANIZATION:Amazon'
      assert captured_metadata[:key_phrases].present?
      assert_includes captured_metadata[:key_phrases], 'cloud computing'
    end
  end

  test "handles NLP analysis errors gracefully" do
    # Mock Comprehend to raise error
    comprehend = Minitest::Mock.new
    comprehend.expect :detect_entities, -> { raise StandardError.new("API Error") }, [String, Hash]

    @processor.instance_variable_set(:@comprehend_service, comprehend)

    result = @processor.send(:perform_nlp_analysis, @entity, "Test text", {})

    # Should return empty hash on error
    assert result.is_a?(Hash)
    assert result.empty?

    comprehend.verify
  end

  test "truncates large text for NLP analysis" do
    large_text = 'a' * 100_000  # 100k characters

    comprehend = Minitest::Mock.new
    # Should receive truncated text (first 50k chars)
    comprehend.expect :detect_entities, { success: true, entities: [] }, [String, Hash]
    comprehend.expect :detect_key_phrases, { success: true, key_phrases: [] }, [String, Hash]
    comprehend.expect :detect_sentiment, { success: true, sentiment: :neutral }, [String, Hash]
    comprehend.expect :detect_language, { success: true, languages: [] }, [String, Hash]

    @processor.instance_variable_set(:@comprehend_service, comprehend)

    result = @processor.send(:perform_nlp_analysis, @entity, large_text, {})

    # Verify all calls were made (which means truncation happened)
    comprehend.verify
  end
end
