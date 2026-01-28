# app/services/aws/comprehend_service.rb
require 'aws-sdk-comprehend'

module Aws
  class ComprehendService
    include Singleton

    attr_reader :client

    # Language codes supported by Comprehend
    SUPPORTED_LANGUAGES = %w[en es fr de it pt ar hi ja ko zh zh-TW].freeze

    # Maximum text sizes for different operations
    MAX_TEXT_SIZE = {
      detect_entities: 100_000,         # 100KB in UTF-8
      detect_sentiment: 5_000,          # 5KB
      detect_key_phrases: 100_000,      # 100KB
      detect_syntax: 100_000,           # 100KB
      detect_pii: 100_000,              # 100KB
      detect_toxic_content: 10_000,     # 10KB
      classify_document: 100_000        # 100KB
    }.freeze

    def initialize
      @client = Aws::Comprehend::Client.new(
        region: ENV.fetch('AWS_REGION', 'us-east-1'),
        credentials: credentials
      )
    end

    # Detect entities in text (people, places, organizations, etc.)
    def detect_entities(text, options = {})
      entity = options[:entity]
      language = options[:language_code] || detect_best_language(text)

      # Truncate text if too long
      text = truncate_text(text, MAX_TEXT_SIZE[:detect_entities])

      response = @client.detect_entities({
        text: text,
        language_code: language
      })

      # Process and enrich entities
      entities = response.entities.map do |entity_item|
        {
          text: entity_item.text,
          type: entity_item.type,
          score: entity_item.score,
          begin_offset: entity_item.begin_offset,
          end_offset: entity_item.end_offset
        }
      end

      # Group entities by type for easier access
      entities_by_type = entities.group_by { |e| e[:type] }

      # Track usage for cost monitoring
      track_usage(entity, :detect_entities, text.length) if entity

      {
        success: true,
        entities: entities,
        entities_by_type: entities_by_type,
        entity_count: entities.count,
        language: language
      }
    rescue => e
      ::Rails.logger.error "Comprehend detect_entities failed: #{e.message}"
      { success: false, error: e.message }
    end

    # Detect sentiment (positive, negative, neutral, mixed)
    def detect_sentiment(text, options = {})
      entity = options[:entity]
      language = options[:language_code] || detect_best_language(text)

      # Sentiment detection has smaller size limit
      text = truncate_text(text, MAX_TEXT_SIZE[:detect_sentiment])

      response = @client.detect_sentiment({
        text: text,
        language_code: language
      })

      sentiment_scores = {
        positive: response.sentiment_score.positive,
        negative: response.sentiment_score.negative,
        neutral: response.sentiment_score.neutral,
        mixed: response.sentiment_score.mixed
      }

      # Determine dominant sentiment
      dominant_sentiment = response.sentiment.downcase.to_sym

      track_usage(entity, :detect_sentiment, text.length) if entity

      {
        success: true,
        sentiment: dominant_sentiment,
        scores: sentiment_scores,
        confidence: sentiment_scores[dominant_sentiment],
        language: language
      }
    rescue => e
      ::Rails.logger.error "Comprehend detect_sentiment failed: #{e.message}"
      { success: false, error: e.message }
    end

    # Detect key phrases in text
    def detect_key_phrases(text, options = {})
      entity = options[:entity]
      language = options[:language_code] || detect_best_language(text)

      text = truncate_text(text, MAX_TEXT_SIZE[:detect_key_phrases])

      response = @client.detect_key_phrases({
        text: text,
        language_code: language
      })

      key_phrases = response.key_phrases.map do |phrase|
        {
          text: phrase.text,
          score: phrase.score,
          begin_offset: phrase.begin_offset,
          end_offset: phrase.end_offset
        }
      end

      # Sort by score for relevance
      key_phrases.sort_by! { |p| -p[:score] }

      track_usage(entity, :detect_key_phrases, text.length) if entity

      {
        success: true,
        key_phrases: key_phrases,
        top_phrases: key_phrases.first(10),
        phrase_count: key_phrases.count,
        language: language
      }
    rescue => e
      ::Rails.logger.error "Comprehend detect_key_phrases failed: #{e.message}"
      { success: false, error: e.message }
    end

    # Detect PII (Personally Identifiable Information)
    def detect_pii(text, options = {})
      entity = options[:entity]
      language = options[:language_code] || 'en'  # PII detection primarily supports English

      text = truncate_text(text, MAX_TEXT_SIZE[:detect_pii])

      response = @client.detect_pii_entities({
        text: text,
        language_code: language
      })

      pii_entities = response.entities.map do |pii|
        {
          type: pii.type,
          score: pii.score,
          begin_offset: pii.begin_offset,
          end_offset: pii.end_offset
        }
      end

      # Group by PII type for analysis
      pii_by_type = pii_entities.group_by { |e| e[:type] }

      track_usage(entity, :detect_pii, text.length) if entity

      {
        success: true,
        entities: pii_entities,
        pii_by_type: pii_by_type,
        contains_pii: pii_entities.any?,
        pii_count: pii_entities.count,
        pii_types: pii_by_type.keys
      }
    rescue => e
      ::Rails.logger.error "Comprehend detect_pii failed: #{e.message}"
      { success: false, error: e.message }
    end

    # Detect language of text
    def detect_language(text, options = {})
      entity = options[:entity]

      # Use first 5000 chars for language detection
      text = text[0..5000]

      response = @client.detect_dominant_language({
        text: text
      })

      languages = response.languages.map do |lang|
        {
          language_code: lang.language_code,
          score: lang.score
        }
      end

      # Sort by confidence score
      languages.sort_by! { |l| -l[:score] }

      track_usage(entity, :detect_language, text.length) if entity

      {
        success: true,
        languages: languages,
        primary_language: languages.first,
        language_code: languages.first&.dig(:language_code)
      }
    rescue => e
      ::Rails.logger.error "Comprehend detect_language failed: #{e.message}"
      { success: false, error: e.message }
    end

    # Detect syntax (parts of speech, tokenization)
    def detect_syntax(text, options = {})
      entity = options[:entity]
      language = options[:language_code] || detect_best_language(text)

      text = truncate_text(text, MAX_TEXT_SIZE[:detect_syntax])

      response = @client.detect_syntax({
        text: text,
        language_code: language
      })

      tokens = response.syntax_tokens.map do |token|
        {
          text: token.text,
          part_of_speech: token.part_of_speech.tag,
          score: token.part_of_speech.score,
          begin_offset: token.begin_offset,
          end_offset: token.end_offset
        }
      end

      # Count parts of speech
      pos_counts = tokens.group_by { |t| t[:part_of_speech] }
                         .transform_values(&:count)

      track_usage(entity, :detect_syntax, text.length) if entity

      {
        success: true,
        tokens: tokens,
        token_count: tokens.count,
        parts_of_speech: pos_counts,
        language: language
      }
    rescue => e
      ::Rails.logger.error "Comprehend detect_syntax failed: #{e.message}"
      { success: false, error: e.message }
    end

    # Detect toxic content (new in 2025)
    def detect_toxic_content(text, options = {})
      entity = options[:entity]
      language = options[:language_code] || 'en'

      text = truncate_text(text, MAX_TEXT_SIZE[:detect_toxic_content])

      # This is a placeholder for the new toxic content API
      # AWS Comprehend is expected to release this in 2025
      # For now, we can use sentiment analysis as a proxy

      sentiment_result = detect_sentiment(text, options)

      if sentiment_result[:success]
        # High negative sentiment might indicate toxic content
        toxicity_score = sentiment_result[:scores][:negative]

        track_usage(entity, :detect_toxic_content, text.length) if entity

        {
          success: true,
          is_toxic: toxicity_score > 0.7,
          toxicity_score: toxicity_score,
          sentiment: sentiment_result[:sentiment],
          language: language
        }
      else
        { success: false, error: "Toxic content detection not available" }
      end
    end

    # Analyze text with multiple operations
    def analyze_text(text, options = {})
      entity = options[:entity]
      operations = options[:operations] || [:entities, :sentiment, :key_phrases, :language]

      results = {
        text_length: text.length,
        analyzed_at: Time.current
      }

      # Detect language first if needed
      if operations.include?(:language) || options[:language_code].nil?
        language_result = detect_language(text, entity: entity)
        results[:language] = language_result
        language_code = language_result[:language_code] if language_result[:success]
      else
        language_code = options[:language_code]
      end

      # Run requested operations
      if operations.include?(:entities)
        results[:entities] = detect_entities(text, entity: entity, language_code: language_code)
      end

      if operations.include?(:sentiment)
        results[:sentiment] = detect_sentiment(text, entity: entity, language_code: language_code)
      end

      if operations.include?(:key_phrases)
        results[:key_phrases] = detect_key_phrases(text, entity: entity, language_code: language_code)
      end

      if operations.include?(:pii)
        results[:pii] = detect_pii(text, entity: entity)
      end

      if operations.include?(:syntax)
        results[:syntax] = detect_syntax(text, entity: entity, language_code: language_code)
      end

      if operations.include?(:toxic_content)
        results[:toxic_content] = detect_toxic_content(text, entity: entity, language_code: language_code)
      end

      results
    end

    # Batch analyze multiple texts
    def batch_analyze(texts, options = {})
      entity = options[:entity]
      operations = options[:operations] || [:entities, :sentiment, :key_phrases]

      results = texts.map.with_index do |text, index|
        ::Rails.logger.info "Analyzing text #{index + 1}/#{texts.count}"

        analysis = analyze_text(text, options)
        analysis[:text_index] = index

        # Add small delay to avoid throttling
        sleep(0.1) if texts.count > 10

        analysis
      end

      {
        total_texts: texts.count,
        operations_performed: operations,
        results: results,
        completed_at: Time.current
      }
    end

    # Create custom classifier (requires training)
    def create_custom_classifier(name, training_data_s3_uri, options = {})
      entity = options[:entity]

      response = @client.create_document_classifier({
        document_classifier_name: name,
        version_name: options[:version] || 'v1',
        data_access_role_arn: comprehend_role_arn,
        input_data_config: {
          data_format: options[:data_format] || 'COMPREHEND_CSV',
          s3_uri: training_data_s3_uri
        },
        output_data_config: {
          s3_uri: "s3://#{ENV['RAG_BUCKET']}/comprehend-classifiers/#{name}/"
        },
        language_code: options[:language_code] || 'en',
        mode: options[:mode] || 'MULTI_CLASS',
        tags: [
          { key: 'Entity', value: entity&.id&.to_s || 'system' },
          { key: 'Environment', value: Rails.env }
        ]
      })

      ::Rails.logger.info "Created custom classifier: #{response.document_classifier_arn}"

      {
        success: true,
        classifier_arn: response.document_classifier_arn,
        status: 'SUBMITTED'
      }
    rescue => e
      ::Rails.logger.error "Failed to create custom classifier: #{e.message}"
      { success: false, error: e.message }
    end

    # Classify document using custom classifier
    def classify_document(text, classifier_arn, options = {})
      entity = options[:entity]

      text = truncate_text(text, MAX_TEXT_SIZE[:classify_document])

      response = @client.classify_document({
        text: text,
        endpoint_arn: classifier_arn
      })

      classes = response.classes.map do |cls|
        {
          name: cls.name,
          score: cls.score,
          page: cls.page
        }
      end

      # Sort by confidence score
      classes.sort_by! { |c| -c[:score] }

      track_usage(entity, :classify_document, text.length) if entity

      {
        success: true,
        classes: classes,
        top_class: classes.first,
        labels: response.labels&.map { |l| { name: l.name, score: l.score } }
      }
    rescue => e
      ::Rails.logger.error "Document classification failed: #{e.message}"
      { success: false, error: e.message }
    end

    # Extract insights for Scout conversations
    def analyze_conversation(messages, entity)
      # Combine messages into conversation text
      conversation_text = messages.map { |m| "#{m[:role]}: #{m[:content]}" }.join("\n\n")

      # Analyze the conversation
      analysis = analyze_text(conversation_text, {
        entity: entity,
        operations: [:sentiment, :entities, :key_phrases, :language]
      })

      # Extract customer intent from key phrases
      customer_intent = extract_customer_intent(analysis[:key_phrases])

      # Detect any potential issues or complaints
      issues_detected = detect_issues(analysis[:sentiment], analysis[:key_phrases])

      {
        conversation_sentiment: analysis[:sentiment],
        customer_intent: customer_intent,
        key_topics: analysis[:key_phrases]&.dig(:top_phrases),
        entities_mentioned: analysis[:entities]&.dig(:entities_by_type),
        issues_detected: issues_detected,
        language: analysis[:language]&.dig(:primary_language),
        analysis_timestamp: Time.current
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

    def comprehend_role_arn
      ENV.fetch('COMPREHEND_ROLE_ARN', "arn:aws:iam::#{account_id}:role/ComprehendServiceRole")
    end

    def account_id
      ENV.fetch('AWS_ACCOUNT_ID', '123456789012')
    end

    def truncate_text(text, max_size)
      # Truncate text to fit within Comprehend's limits
      return text if text.bytesize <= max_size

      # Truncate and ensure valid UTF-8
      truncated = text.byteslice(0, max_size)
      truncated.force_encoding('UTF-8')

      # Remove any incomplete UTF-8 sequences at the end
      truncated.scrub('')
    end

    def detect_best_language(text)
      # Quick language detection for first 1000 chars
      sample = text[0..1000]
      result = detect_language(sample)

      if result[:success] && result[:language_code]
        # Ensure it's a supported language
        lang = result[:language_code]
        SUPPORTED_LANGUAGES.include?(lang) ? lang : 'en'
      else
        'en'  # Default to English
      end
    end

    def track_usage(entity, operation, text_length)
      return unless entity

      # Calculate units (100 characters = 1 unit)
      units = (text_length / 100.0).ceil

      # Get operation cost
      operation_key = operation.to_sym
      rate = Aws::CostCalculator::PRICING[:comprehend][operation_key] || 0.00008

      cost = units * rate

      # Track with EntityCostTracker
      tracker = EntityCostTracker.new(entity)
      tracker.track_usage(
        category: :analytics,
        service: :comprehend,
        usage_type: operation,
        quantity: units,
        metadata: {
          text_length: text_length,
          cost_usd: cost
        }
      )

      ::Rails.logger.info "Tracked Comprehend usage: #{operation} for entity #{entity.id}, cost: $#{cost.round(6)}"
    end

    def extract_customer_intent(key_phrases_result)
      return nil unless key_phrases_result&.dig(:success)

      # Look for action-oriented phrases
      phrases = key_phrases_result[:top_phrases] || []

      action_keywords = ['want', 'need', 'looking for', 'help', 'create', 'build', 'fix', 'update', 'change', 'add']

      intent_phrases = phrases.select do |phrase|
        action_keywords.any? { |keyword| phrase[:text].downcase.include?(keyword) }
      end

      intent_phrases.first(3).map { |p| p[:text] }
    end

    def detect_issues(sentiment_result, key_phrases_result)
      issues = []

      # Check for negative sentiment
      if sentiment_result&.dig(:success) && sentiment_result[:sentiment] == :negative
        issues << {
          type: 'negative_sentiment',
          severity: sentiment_result[:scores][:negative] > 0.8 ? 'high' : 'medium',
          confidence: sentiment_result[:scores][:negative]
        }
      end

      # Check for complaint-related key phrases
      if key_phrases_result&.dig(:success)
        complaint_keywords = ['problem', 'issue', 'error', 'broken', 'not working', 'failed', 'bug', 'complaint']

        phrases = key_phrases_result[:key_phrases] || []
        complaint_phrases = phrases.select do |phrase|
          complaint_keywords.any? { |keyword| phrase[:text].downcase.include?(keyword) }
        end

        if complaint_phrases.any?
          issues << {
            type: 'complaint_detected',
            severity: 'medium',
            phrases: complaint_phrases.map { |p| p[:text] }
          }
        end
      end

      issues
    end
  end
end