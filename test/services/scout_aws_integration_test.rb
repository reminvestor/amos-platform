# test/services/scout_aws_integration_test.rb
require "test_helper"

class ScoutAwsIntegrationTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @entity.update!(
      name: 'Test Company',
      business_description: 'A software company'
    )

    @integration = ScoutAwsIntegration.instance
  end

  test "singleton pattern works" do
    assert_same @integration, ScoutAwsIntegration.instance
  end

  test "initializes with required services" do
    assert @integration.kb_service.present?
    assert @integration.comprehend_service.present?
    assert @integration.document_processor.present?
  end

  test "processes user message successfully" do
    message = "What is AWS Lambda?"
    session_id = SecureRandom.uuid

    # Mock Comprehend service
    comprehend = Minitest::Mock.new
    comprehend.expect :analyze_text, {
      language: { success: true, primary_language: { language_code: 'en' } },
      sentiment: { success: true, sentiment: :neutral, scores: { neutral: 0.9 } },
      entities: { success: true, entities: [], entity_count: 0 },
      key_phrases: { success: true, key_phrases: [], phrase_count: 0 },
      pii: { success: true, contains_pii: false }
    }, [String, Hash]
    comprehend.expect :detect_sentiment, {
      success: true,
      sentiment: :neutral
    }, [String, Hash]

    # Mock KB service
    kb_service = Minitest::Mock.new
    kb_service.expect :retrieve_and_generate, {
      response: 'AWS Lambda is a serverless compute service',
      session_id: session_id,
      citations: []
    }, [Entity, String, String, Hash]

    EntityCostTracker.stub :new, Minitest::Mock.new do
      @integration.stub :comprehend_service, comprehend do
        @integration.stub :kb_service, kb_service do
          result = @integration.process_message(@entity, message, session_id)

          assert result[:success]
          assert result[:response].present?
          assert_equal session_id, result[:session_id]
          assert result[:message_analysis].present?
        end
      end
    end

    comprehend.verify
    kb_service.verify
  end

  test "processes message with uploaded files" do
    message = "Analyze this document"
    test_file = Rails.root.join('tmp', 'test_scout.txt')
    File.write(test_file, 'Test content')

    # Mock document processor
    doc_processor = Minitest::Mock.new
    doc_processor.expect :process_document, {
      success: true,
      file_name: 'test_scout.txt',
      extracted_text: 'Test content',
      nlp_insights: { entities: [], key_phrases: [] },
      rag_document_id: 1
    }, [Entity, String, Hash]

    # Mock other services
    comprehend = Minitest::Mock.new
    comprehend.expect :analyze_text, {
      language: { success: true },
      sentiment: { success: true, sentiment: :neutral },
      entities: { success: true },
      key_phrases: { success: true },
      pii: { success: true }
    }, [String, Hash]
    comprehend.expect :detect_sentiment, { success: true, sentiment: :neutral }, [String, Hash]

    kb_service = Minitest::Mock.new
    kb_service.expect :retrieve_and_generate, {
      response: 'Analysis complete',
      session_id: 'session-123',
      citations: []
    }, [Entity, String, NilClass, Hash]

    EntityCostTracker.stub :new, Minitest::Mock.new do
      @integration.stub :document_processor, doc_processor do
        @integration.stub :comprehend_service, comprehend do
          @integration.stub :kb_service, kb_service do
            result = @integration.process_message(@entity, message, nil, {
              uploaded_files: [test_file]
            })

            assert result[:success]
            assert result[:processed_files].present?
            assert_equal 1, result[:processed_files].count
          end
        end
      end
    end

    FileUtils.rm_f(test_file)
    doc_processor.verify
    comprehend.verify
    kb_service.verify
  end

  test "handles processing errors gracefully" do
    message = "Test message"

    # Mock Comprehend to raise error
    comprehend = Minitest::Mock.new
    comprehend.expect :analyze_text, -> { raise StandardError.new("API Error") }, [String, Hash]

    @integration.stub :comprehend_service, comprehend do
      result = @integration.process_message(@entity, message)

      assert_not result[:success]
      assert result[:error].present?
      assert result[:response].present?  # Fallback response
    end

    comprehend.verify
  end

  test "processes document upload successfully" do
    test_file = Rails.root.join('tmp', 'upload_test.txt')
    File.write(test_file, 'Document content for testing')

    # Mock document processor
    doc_processor = Minitest::Mock.new
    doc_processor.expect :process_document, {
      success: true,
      file_name: 'upload_test.txt',
      extracted_text: 'Document content',
      nlp_insights: {
        entities_by_type: { 'ORGANIZATION' => [{ text: 'Test' }] },
        key_phrases: { top_phrases: [{ text: 'document content', score: 0.9 }] },
        sentiment: { sentiment: :neutral }
      },
      processing_time: 1.5,
      rag_document_id: 1
    }, [Entity, String, Hash]

    @integration.stub :document_processor, doc_processor do
      result = @integration.process_document_upload(@entity, test_file)

      assert result[:success]
      assert_equal 'upload_test.txt', result[:file_name]
      assert result[:summary].present?
      assert result[:key_entities].present?
      assert result[:key_phrases].present?
    end

    FileUtils.rm_f(test_file)
    doc_processor.verify
  end

  test "queries knowledge base with enhanced context" do
    query = "What is cloud computing?"

    # Mock Comprehend
    comprehend = Minitest::Mock.new
    comprehend.expect :analyze_text, {
      entities: { success: true, entities: [{ text: 'cloud computing', type: 'TITLE' }] },
      key_phrases: { success: true, top_phrases: [{ text: 'cloud computing', score: 0.95 }] },
      sentiment: { success: true, sentiment: :neutral }
    }, [String, Hash]

    # Mock KB service
    kb_service = Minitest::Mock.new
    kb_service.expect :query, {
      query: query,
      results: [
        { content: 'Cloud computing is...', score: 0.9, metadata: {} }
      ]
    }, [Entity, String, Hash]

    @integration.stub :comprehend_service, comprehend do
      @integration.stub :kb_service, kb_service do
        result = @integration.query_knowledge(@entity, query)

        assert_equal query, result[:query]
        assert result[:results].present?
        assert result[:query_analysis].present?
        assert result[:search_terms].present?
      end
    end

    comprehend.verify
    kb_service.verify
  end

  test "gets conversation insights" do
    messages = [
      { role: 'user', content: 'I need to create a new campaign', timestamp: 1.hour.ago },
      { role: 'assistant', content: 'I can help you with that', timestamp: 59.minutes.ago },
      { role: 'user', content: 'Let me follow up tomorrow', timestamp: 58.minutes.ago }
    ]

    # Mock Comprehend
    comprehend = Minitest::Mock.new
    comprehend.expect :analyze_conversation, {
      conversation_sentiment: { sentiment: :positive },
      key_topics: [{ text: 'campaign', score: 0.9 }],
      issues_detected: []
    }, [Array, Entity]

    # Mock KB service
    kb_service = Minitest::Mock.new
    kb_service.expect :query, {
      results: [{ content: 'Campaign info', score: 0.8 }]
    }, [Entity, String, Hash]

    @integration.stub :comprehend_service, comprehend do
      @integration.stub :kb_service, kb_service do
        insights = @integration.get_conversation_insights(@entity, messages)

        assert insights[:conversation_sentiment].present?
        assert insights[:key_topics].present?
        assert insights[:related_knowledge].present?
        assert insights[:action_items].present?
        assert_equal 3, insights[:metrics][:message_count]
      end
    end

    comprehend.verify
    kb_service.verify
  end

  test "processes message for workflow execution" do
    message = "Create a new marketing campaign for our product launch"

    # Mock Comprehend
    comprehend = Minitest::Mock.new
    comprehend.expect :analyze_text, {
      entities: {
        success: true,
        entities_by_type: {
          'EVENT' => [{ text: 'product launch', score: 0.9 }]
        }
      },
      key_phrases: {
        success: true,
        key_phrases: [{ text: 'create marketing campaign', score: 0.95 }]
      },
      sentiment: { success: true, sentiment: :positive },
      pii: { success: true, contains_pii: false }
    }, [String, Hash]

    # Mock KB service
    kb_service = Minitest::Mock.new
    kb_service.expect :query, {
      results: [{ content: 'Campaign workflow steps', score: 0.9 }]
    }, [Entity, String, Hash]

    @integration.stub :comprehend_service, comprehend do
      @integration.stub :kb_service, kb_service do
        data = @integration.process_for_workflow(@entity, message)

        assert data[:entities].present?
        assert_equal 'create', data[:intent]
        assert data[:workflow_context].present?
      end
    end

    comprehend.verify
    kb_service.verify
  end

  test "selects Haiku model for simple queries" do
    analysis = {
      entities: { entity_count: 1 },
      key_phrases: { phrase_count: 2 }
    }

    model = @integration.send(:select_optimal_model, analysis, {})

    assert_includes model, 'haiku'
  end

  test "selects Sonnet model for complex queries" do
    analysis = {
      entities: { entity_count: 5 },
      key_phrases: { phrase_count: 10 }
    }

    model = @integration.send(:select_optimal_model, analysis, {})

    assert_includes model, 'sonnet'
  end

  test "prefers fast model when requested" do
    analysis = {
      entities: { entity_count: 100 },
      key_phrases: { phrase_count: 100 }
    }

    model = @integration.send(:select_optimal_model, analysis, { prefer_fast_model: true })

    assert_includes model, 'haiku'
  end

  test "determines low temperature for factual queries" do
    analysis = {
      entities: {
        entities_by_type: {
          'ORGANIZATION' => [{ text: 'AWS' }],
          'DATE' => [{ text: '2024' }]
        }
      }
    }

    temp = @integration.send(:determine_temperature, analysis)

    assert_equal 0.3, temp
  end

  test "determines high temperature for creative queries" do
    analysis = {
      entities: { entities_by_type: {} }
    }

    temp = @integration.send(:determine_temperature, analysis)

    assert_equal 0.7, temp
  end

  test "builds enhanced prompt with language context" do
    message = "Test message"
    analysis = {
      language: {
        primary_language: { language_code: 'es' }
      }
    }

    prompt = @integration.send(:build_enhanced_prompt, message, analysis)

    assert_includes prompt, '[User language: es]'
  end

  test "builds enhanced prompt with strong sentiment" do
    message = "This is frustrating"
    analysis = {
      language: { primary_language: { language_code: 'en' } },
      sentiment: {
        sentiment: :negative,
        scores: { negative: 0.95 }
      }
    }

    prompt = @integration.send(:build_enhanced_prompt, message, analysis)

    assert_includes prompt, '[User sentiment: negative]'
  end

  test "builds system prompt with entity context" do
    prompt = @integration.send(:build_system_prompt, @entity, {})

    assert_includes prompt, 'Test Company'
    assert_includes prompt, 'A software company'
  end

  test "extracts search terms from query analysis" do
    query_analysis = {
      entities: {
        entities: [
          { text: 'AWS Lambda', type: 'TITLE' },
          { text: 'Amazon', type: 'ORGANIZATION' }
        ]
      },
      key_phrases: {
        top_phrases: [
          { text: 'serverless computing', score: 0.9 },
          { text: 'event-driven', score: 0.85 }
        ]
      }
    }

    terms = @integration.send(:extract_search_terms, query_analysis)

    assert_includes terms, 'AWS Lambda'
    assert_includes terms, 'Amazon'
    assert_includes terms, 'serverless computing'
  end

  test "ranks search results based on sentiment match" do
    results = [
      { content: 'Result 1', score: 0.7, metadata: { 'sentiment' => 'positive' } },
      { content: 'Result 2', score: 0.8, metadata: { 'sentiment' => 'neutral' } },
      { content: 'Result 3', score: 0.6, metadata: { 'sentiment' => 'positive' } }
    ]

    query_analysis = {
      sentiment: { sentiment: :positive }
    }

    ranked = @integration.send(:rank_search_results, results, query_analysis)

    # Results with matching sentiment should be boosted
    assert ranked.first[:adjusted_score] >= ranked.last[:adjusted_score]
  end

  test "detects action items in conversation" do
    messages = [
      { role: 'user', content: 'I need to complete this task by Friday', timestamp: Time.current },
      { role: 'assistant', content: 'Understood', timestamp: Time.current },
      { role: 'user', content: 'Let me follow up next week', timestamp: Time.current }
    ]

    action_items = @integration.send(:detect_action_items, messages)

    assert action_items.any?
    assert action_items.any? { |item| item[:detected_keyword] == 'need to' }
    assert action_items.any? { |item| item[:detected_keyword] == 'follow up' }
  end

  test "extracts workflow entities correctly" do
    entities_result = {
      success: true,
      entities_by_type: {
        'PERSON' => [{ text: 'John Doe', score: 0.95 }],
        'ORGANIZATION' => [{ text: 'Acme Corp', score: 0.92 }],
        'DATE' => [{ text: 'January 15th', score: 0.88 }]
      }
    }

    extracted = @integration.send(:extract_workflow_entities, entities_result)

    assert_equal ['John Doe'], extracted[:people]
    assert_equal ['Acme Corp'], extracted[:organizations]
    assert_equal ['January 15th'], extracted[:dates]
  end

  test "determines user intent from key phrases" do
    # Test 'create' intent
    result_create = {
      success: true,
      key_phrases: [
        { text: 'create new campaign', score: 0.9 }
      ]
    }
    assert_equal 'create', @integration.send(:determine_user_intent, result_create)

    # Test 'search' intent
    result_search = {
      success: true,
      key_phrases: [
        { text: 'find information about', score: 0.9 }
      ]
    }
    assert_equal 'search', @integration.send(:determine_user_intent, result_search)

    # Test 'send' intent
    result_send = {
      success: true,
      key_phrases: [
        { text: 'send email to customers', score: 0.9 }
      ]
    }
    assert_equal 'send', @integration.send(:determine_user_intent, result_send)
  end

  test "generates document summary with NLP insights" do
    processing_result = {
      extracted_text: 'This is a test document about cloud computing and AWS services. It discusses various features and benefits.',
      nlp_insights: {
        key_phrases: {
          top_phrases: [
            { text: 'cloud computing', score: 0.95 },
            { text: 'AWS services', score: 0.92 }
          ]
        },
        entities_by_type: {
          'ORGANIZATION' => [{ text: 'AWS', score: 0.9 }]
        },
        sentiment: { sentiment: :positive }
      }
    }

    summary = @integration.send(:generate_document_summary, @entity, processing_result)

    assert summary.present?
    assert_includes summary, 'cloud computing'
    assert_includes summary, 'AWS'
    assert_includes summary, 'positive'
  end

  test "generates fallback response" do
    message = "What is the meaning of life?"

    response = @integration.send(:generate_fallback_response, message)

    assert response.present?
    assert_includes response, message
    assert_includes response, 'unable to access'
  end

  test "tracks conversation costs" do
    message = "Test message"
    response = "This is a longer response with more content to test token estimation"

    mock_tracker = Minitest::Mock.new
    mock_tracker.expect :track_scout_conversation, nil, [Hash]

    EntityCostTracker.stub :new, mock_tracker do
      @integration.send(:track_conversation_costs, @entity, message, response)
    end

    mock_tracker.verify
  end
end
