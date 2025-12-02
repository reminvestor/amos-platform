# test/services/aws/comprehend_service_test.rb
require "test_helper"

module Aws
  class ComprehendServiceTest < ActiveSupport::TestCase
    setup do
      @service = ComprehendService.instance
      @entity = entities(:one)
      @sample_text = "John Smith works at Amazon in Seattle. He loves the innovative technology."
    end

    test "singleton pattern works" do
      assert_same @service, ComprehendService.instance
    end

    test "detects entities in text" do
      mock_response = OpenStruct.new(
        entities: [
          OpenStruct.new(text: "John Smith", type: "PERSON", score: 0.99, begin_offset: 0, end_offset: 10),
          OpenStruct.new(text: "Amazon", type: "ORGANIZATION", score: 0.98, begin_offset: 20, end_offset: 26),
          OpenStruct.new(text: "Seattle", type: "LOCATION", score: 0.97, begin_offset: 30, end_offset: 37)
        ]
      )

      @service.client.stub :detect_entities, mock_response do
        result = @service.detect_entities(@sample_text, entity: @entity)

        assert result[:success]
        assert_equal 3, result[:entity_count]
        assert_equal "John Smith", result[:entities].first[:text]
        assert_equal "PERSON", result[:entities].first[:type]
        assert result[:entities_by_type]["PERSON"].present?
        assert result[:entities_by_type]["ORGANIZATION"].present?
      end
    end

    test "detects sentiment" do
      mock_response = OpenStruct.new(
        sentiment: "POSITIVE",
        sentiment_score: OpenStruct.new(
          positive: 0.95,
          negative: 0.01,
          neutral: 0.03,
          mixed: 0.01
        )
      )

      @service.client.stub :detect_sentiment, mock_response do
        result = @service.detect_sentiment(@sample_text, entity: @entity)

        assert result[:success]
        assert_equal :positive, result[:sentiment]
        assert_equal 0.95, result[:scores][:positive]
        assert_equal 0.95, result[:confidence]
      end
    end

    test "detects key phrases" do
      mock_response = OpenStruct.new(
        key_phrases: [
          OpenStruct.new(text: "innovative technology", score: 0.99, begin_offset: 50, end_offset: 71),
          OpenStruct.new(text: "John Smith", score: 0.95, begin_offset: 0, end_offset: 10),
          OpenStruct.new(text: "Amazon", score: 0.90, begin_offset: 20, end_offset: 26)
        ]
      )

      @service.client.stub :detect_key_phrases, mock_response do
        result = @service.detect_key_phrases(@sample_text, entity: @entity)

        assert result[:success]
        assert_equal 3, result[:phrase_count]
        assert_equal "innovative technology", result[:top_phrases].first[:text]
        assert_equal 0.99, result[:top_phrases].first[:score]
      end
    end

    test "detects PII" do
      pii_text = "My SSN is 123-45-6789 and email is john@example.com"

      mock_response = OpenStruct.new(
        entities: [
          OpenStruct.new(type: "SSN", score: 0.99, begin_offset: 10, end_offset: 21),
          OpenStruct.new(type: "EMAIL", score: 0.98, begin_offset: 35, end_offset: 52)
        ]
      )

      @service.client.stub :detect_pii_entities, mock_response do
        result = @service.detect_pii(pii_text, entity: @entity)

        assert result[:success]
        assert result[:contains_pii]
        assert_equal 2, result[:pii_count]
        assert_includes result[:pii_types], "SSN"
        assert_includes result[:pii_types], "EMAIL"
      end
    end

    test "detects language" do
      mock_response = OpenStruct.new(
        languages: [
          OpenStruct.new(language_code: "en", score: 0.99),
          OpenStruct.new(language_code: "es", score: 0.01)
        ]
      )

      @service.client.stub :detect_dominant_language, mock_response do
        result = @service.detect_language(@sample_text, entity: @entity)

        assert result[:success]
        assert_equal "en", result[:language_code]
        assert_equal 0.99, result[:primary_language][:score]
      end
    end

    test "detects syntax and parts of speech" do
      mock_response = OpenStruct.new(
        syntax_tokens: [
          OpenStruct.new(
            text: "John",
            part_of_speech: OpenStruct.new(tag: "NOUN", score: 0.99),
            begin_offset: 0,
            end_offset: 4
          ),
          OpenStruct.new(
            text: "works",
            part_of_speech: OpenStruct.new(tag: "VERB", score: 0.98),
            begin_offset: 11,
            end_offset: 16
          )
        ]
      )

      @service.client.stub :detect_syntax, mock_response do
        result = @service.detect_syntax(@sample_text, entity: @entity)

        assert result[:success]
        assert_equal 2, result[:token_count]
        assert_equal 1, result[:parts_of_speech]["NOUN"]
        assert_equal 1, result[:parts_of_speech]["VERB"]
      end
    end

    test "analyzes text with multiple operations" do
      @service.stub :detect_language, { success: true, language_code: "en" } do
        @service.stub :detect_entities, { success: true, entities: [], entity_count: 0 } do
          @service.stub :detect_sentiment, { success: true, sentiment: :positive } do
            @service.stub :detect_key_phrases, { success: true, key_phrases: [] } do
              result = @service.analyze_text(@sample_text, {
                entity: @entity,
                operations: [:language, :entities, :sentiment, :key_phrases]
              })

              assert result[:language][:success]
              assert result[:entities][:success]
              assert result[:sentiment][:success]
              assert result[:key_phrases][:success]
              assert result[:analyzed_at].present?
            end
          end
        end
      end
    end

    test "batch analyzes multiple texts" do
      texts = ["First text", "Second text", "Third text"]

      @service.stub :analyze_text, ->(*args) { { success: true } } do
        result = @service.batch_analyze(texts, entity: @entity)

        assert_equal 3, result[:total_texts]
        assert_equal 3, result[:results].count
        assert result[:completed_at].present?
      end
    end

    test "truncates long text to fit limits" do
      long_text = "a" * 200_000  # 200K chars
      truncated = @service.send(:truncate_text, long_text, 100_000)

      assert truncated.bytesize <= 100_000
      assert truncated.valid_encoding?
    end

    test "detects best language for text" do
      @service.stub :detect_language, { success: true, language_code: "fr" } do
        lang = @service.send(:detect_best_language, "Bonjour")
        assert_equal "fr", lang
      end
    end

    test "handles unsupported language gracefully" do
      @service.stub :detect_language, { success: true, language_code: "xx" } do
        lang = @service.send(:detect_best_language, "Unknown language")
        assert_equal "en", lang  # Falls back to English
      end
    end

    test "tracks usage for cost monitoring" do
      text = "Test text for cost tracking"

      assert_difference 'EntityUsageMetric.count', 1 do
        @service.send(:track_usage, @entity, :detect_entities, text.length)
      end

      metric = EntityUsageMetric.last
      assert_equal @entity, metric.entity
      assert_equal 'analytics', metric.category
      assert_equal 'comprehend', metric.service
    end

    test "analyzes conversation for Scout" do
      messages = [
        { role: 'user', content: 'I need help with my account' },
        { role: 'assistant', content: 'I can help you with that' },
        { role: 'user', content: 'There is a problem with billing' }
      ]

      @service.stub :analyze_text, {
        sentiment: { success: true, sentiment: :negative, scores: { negative: 0.8 } },
        key_phrases: { success: true, key_phrases: [{ text: 'billing problem', score: 0.9 }], top_phrases: [{ text: 'billing problem', score: 0.9 }] },
        entities: { success: true, entities_by_type: {} },
        language: { success: true, primary_language: { language_code: 'en' } }
      } do
        result = @service.analyze_conversation(messages, @entity)

        assert result[:conversation_sentiment].present?
        assert result[:key_topics].present?
        assert result[:issues_detected].any?
        assert result[:analysis_timestamp].present?
      end
    end

    test "detects toxic content" do
      # Placeholder for future API
      text = "This is negative text"

      result = @service.detect_toxic_content(text, entity: @entity)

      # Currently uses sentiment as proxy
      assert result.key?(:toxicity_score)
    end

    test "classifies document with custom classifier" do
      classifier_arn = "arn:aws:comprehend:us-east-1:123:classifier/test"

      mock_response = OpenStruct.new(
        classes: [
          OpenStruct.new(name: "Technology", score: 0.95, page: nil),
          OpenStruct.new(name: "Business", score: 0.75, page: nil)
        ],
        labels: []
      )

      @service.client.stub :classify_document, mock_response do
        result = @service.classify_document(@sample_text, classifier_arn, entity: @entity)

        assert result[:success]
        assert_equal "Technology", result[:top_class][:name]
        assert_equal 0.95, result[:top_class][:score]
      end
    end

    test "handles API errors gracefully" do
      @service.client.stub :detect_entities, ->(*args) { raise StandardError.new("API Error") } do
        result = @service.detect_entities(@sample_text)

        assert_not result[:success]
        assert result[:error].present?
        assert_includes result[:error], "API Error"
      end
    end

    test "extracts customer intent from key phrases" do
      key_phrases_result = {
        success: true,
        top_phrases: [
          { text: "want to create account", score: 0.95 },
          { text: "need help with setup", score: 0.90 },
          { text: "looking for documentation", score: 0.85 }
        ]
      }

      intents = @service.send(:extract_customer_intent, key_phrases_result)

      assert intents.is_a?(Array)
      assert_includes intents, "want to create account"
      assert_includes intents, "need help with setup"
    end

    test "detects issues from sentiment and phrases" do
      sentiment_result = { success: true, sentiment: :negative, scores: { negative: 0.9 } }
      key_phrases_result = {
        success: true,
        key_phrases: [
          { text: "problem with service", score: 0.95 },
          { text: "not working properly", score: 0.90 }
        ]
      }

      issues = @service.send(:detect_issues, sentiment_result, key_phrases_result)

      assert issues.any?
      assert issues.any? { |i| i[:type] == 'negative_sentiment' }
      assert issues.any? { |i| i[:type] == 'complaint_detected' }
    end
  end
end