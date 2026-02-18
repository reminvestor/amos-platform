# app/services/scout_aws_integration.rb
# Integration service for Scout chatbot with AWS Bedrock, Comprehend, and Textract
class ScoutAwsIntegration
  include Singleton

  attr_reader :kb_service, :comprehend_service, :document_processor

  def initialize
    @kb_service = Aws::BedrockKnowledgeBaseService.instance
    @comprehend_service = Aws::ComprehendService.instance
    @document_processor = DocumentProcessorV2.instance
  end

  # Process user message with full AWS integration
  def process_message(entity, message, session_id = nil, options = {})
    result = {
      message: message,
      timestamp: Time.current,
      session_id: session_id
    }

    begin
      # Step 1: Analyze the user's message with Comprehend
      message_analysis = analyze_user_message(entity, message)
      result[:message_analysis] = message_analysis

      # Step 2: Check for uploaded files in the session
      if options[:uploaded_files]&.any?
        file_results = process_uploaded_files(entity, options[:uploaded_files])
        result[:processed_files] = file_results
      end

      # Step 3: Generate response using Bedrock KB with RAG
      response = generate_response(entity, message, session_id, message_analysis, options)
      result[:response] = response[:response]
      result[:citations] = response[:citations]
      result[:session_id] = response[:session_id]

      # Step 4: Analyze response sentiment for quality monitoring
      if result[:response]
        response_analysis = @comprehend_service.detect_sentiment(
          result[:response],
          entity: entity
        )
        result[:response_sentiment] = response_analysis[:sentiment] if response_analysis[:success]
      end

      # Track conversation costs
      track_conversation_costs(entity, message, result[:response])

      result[:success] = true

    rescue => e
      Rails.logger.error "Scout AWS integration failed: #{e.message}\n#{e.backtrace.join("\n")}"
      result[:success] = false
      result[:error] = e.message

      # Fallback to basic response without KB
      result[:response] = generate_fallback_response(message)
    end

    result
  end

  # Process document upload for knowledge extraction
  def process_document_upload(entity, file_path, options = {})
    Rails.logger.info "Processing document upload for entity #{entity.id}: #{file_path}"

    # Use the enhanced document processor
    processing_result = @document_processor.process_document(entity, file_path, options)

    if processing_result[:success]
      # Extract key information for immediate use
      summary = generate_document_summary(entity, processing_result)

      {
        success: true,
        file_name: processing_result[:file_name],
        summary: summary,
        key_entities: processing_result.dig(:nlp_insights, :entities_by_type),
        key_phrases: processing_result.dig(:nlp_insights, :key_phrases, :top_phrases),
        sentiment: processing_result.dig(:nlp_insights, :sentiment),
        processing_time: processing_result[:processing_time],
        rag_document_id: processing_result[:rag_document_id]
      }
    else
      {
        success: false,
        error: processing_result[:error]
      }
    end
  end

  # Query knowledge base with enhanced context
  def query_knowledge(entity, query, options = {})
    # Analyze query first
    query_analysis = @comprehend_service.analyze_text(query, {
      entity: entity,
      operations: [:entities, :key_phrases, :sentiment]
    })

    # Extract entities and key phrases for better search
    search_terms = extract_search_terms(query_analysis)

    # Query the knowledge base with enhanced context
    kb_results = @kb_service.query(entity, query, {
      max_results: options[:max_results] || 5,
      search_type: 'HYBRID',
      filters: build_search_filters(search_terms, options)
    })

    # Rank results based on relevance and sentiment alignment
    ranked_results = rank_search_results(kb_results[:results], query_analysis)

    {
      query: query,
      results: ranked_results,
      query_analysis: query_analysis,
      search_terms: search_terms,
      result_count: ranked_results.count
    }
  end

  # Get conversation insights
  def get_conversation_insights(entity, messages)
    # Analyze entire conversation
    insights = @comprehend_service.analyze_conversation(messages, entity)

    # Add knowledge base context
    if insights[:key_topics]&.any?
      # Search KB for related information
      top_topic = insights[:key_topics].first[:text]
      kb_context = @kb_service.query(entity, top_topic, max_results: 3)
      insights[:related_knowledge] = kb_context[:results]
    end

    # Detect action items or follow-ups
    insights[:action_items] = detect_action_items(messages)

    # Calculate conversation metrics
    insights[:metrics] = {
      message_count: messages.count,
      avg_message_length: messages.sum { |m| m[:content].length } / messages.count,
      user_messages: messages.count { |m| m[:role] == 'user' },
      assistant_messages: messages.count { |m| m[:role] == 'assistant' }
    }

    insights
  end

  # Process Scout conversation for workflow execution
  def process_for_workflow(entity, message, context = {})
    # Enhanced analysis for workflow planning
    analysis = @comprehend_service.analyze_text(message, {
      entity: entity,
      operations: [:entities, :key_phrases, :sentiment, :pii]
    })

    # Extract structured data for workflow
    extracted_data = {
      entities: extract_workflow_entities(analysis[:entities]),
      intent: determine_user_intent(analysis[:key_phrases]),
      sentiment: analysis.dig(:sentiment, :sentiment),
      contains_pii: analysis.dig(:pii, :contains_pii)
    }

    # Query KB for relevant workflow context
    if extracted_data[:intent]
      kb_context = @kb_service.query(
        entity,
        "#{extracted_data[:intent]} workflow process",
        max_results: 3
      )
      extracted_data[:workflow_context] = kb_context[:results]
    end

    # Check for required data from previous messages or documents
    if context[:session_id]
      session_data = retrieve_session_context(entity, context[:session_id])
      extracted_data[:session_context] = session_data
    end

    extracted_data
  end

  private

  def analyze_user_message(entity, message)
    @comprehend_service.analyze_text(message, {
      entity: entity,
      operations: [:language, :sentiment, :entities, :key_phrases, :pii]
    })
  end

  def process_uploaded_files(entity, file_paths)
    results = []

    file_paths.each do |file_path|
      result = process_document_upload(entity, file_path, {
        enable_nlp: true,
        detect_pii: true
      })
      results << result
    end

    results
  end

  def generate_response(entity, message, session_id, message_analysis, options)
    # Build enhanced prompt with analysis context
    enhanced_prompt = build_enhanced_prompt(message, message_analysis)

    # Determine which model to use based on complexity
    model_arn = select_optimal_model(message_analysis, options)

    # Generate response with Bedrock KB
    @kb_service.retrieve_and_generate(
      entity,
      enhanced_prompt,
      session_id,
      {
        model_arn: model_arn,
        max_tokens: options[:max_tokens] || 2048,
        temperature: determine_temperature(message_analysis),
        system_prompt: build_system_prompt(entity, options)
      }
    )
  end

  def build_enhanced_prompt(message, analysis)
    # Add context from analysis
    prompt = message

    # Add language context if not English
    if analysis.dig(:language, :primary_language, :language_code) != 'en'
      lang_name = analysis.dig(:language, :primary_language, :language_code)
      prompt = "[User language: #{lang_name}] #{prompt}"
    end

    # Add sentiment context if strongly emotional
    sentiment = analysis.dig(:sentiment, :sentiment)
    if sentiment && [:negative, :positive].include?(sentiment)
      sentiment_score = analysis.dig(:sentiment, :scores, sentiment)
      if sentiment_score > 0.8
        prompt = "[User sentiment: #{sentiment}] #{prompt}"
      end
    end

    prompt
  end

  def select_optimal_model(analysis, options)
    # Use cost-effective models for simple queries
    if options[:prefer_fast_model]
      return "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-5-haiku-20241022-v1:0"
    end

    # Check complexity indicators
    entities_count = analysis.dig(:entities, :entity_count) || 0
    key_phrases_count = analysis.dig(:key_phrases, :phrase_count) || 0

    # Simple queries can use Haiku
    if entities_count < 3 && key_phrases_count < 5
      "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-5-haiku-20241022-v1:0"
    else
      # Complex queries use Sonnet
      "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-sonnet-4-6"
    end
  end

  def determine_temperature(analysis)
    # Lower temperature for factual queries
    entities = analysis.dig(:entities, :entities_by_type) || {}

    # If asking about specific entities, use lower temperature
    if entities['ORGANIZATION'] || entities['PERSON'] || entities['DATE']
      0.3
    else
      # Higher temperature for creative tasks
      0.7
    end
  end

  def build_system_prompt(entity, options)
    current_time = Time.current.in_time_zone('America/Los_Angeles')
    
    base_prompt = <<~PROMPT
      You are Amos, an AI assistant for #{entity.name}.
      
      📅 CURRENT DATE/TIME: #{current_time.strftime("%A, %B %d, %Y at %I:%M %p %Z")}
      
      You have access to their knowledge base and can help with various tasks.
      Always be helpful, accurate, and professional.
    PROMPT

    # Add entity-specific context
    if entity.business_description
      base_prompt += "\n\nAbout the business: #{entity.business_description}"
    end

    # Add any custom instructions
    if options[:system_instructions]
      base_prompt += "\n\n#{options[:system_instructions]}"
    end

    base_prompt
  end

  def generate_fallback_response(message)
    "I understand you're asking about: #{message}. However, I'm currently unable to access the full knowledge base. Please try again in a moment, or let me help you with something else."
  end

  def generate_document_summary(entity, processing_result)
    return nil unless processing_result[:extracted_text]

    # Use first 2000 chars for summary
    text_sample = processing_result[:extracted_text][0..2000]

    # Get key phrases for summary
    key_phrases = processing_result.dig(:nlp_insights, :key_phrases, :top_phrases) || []
    top_phrases = key_phrases.first(5).map { |p| p[:text] }.join(', ')

    # Get main entities
    entities = processing_result.dig(:nlp_insights, :entities_by_type) || {}
    main_entities = entities.values.flatten.first(5).map { |e| e[:text] }.join(', ')

    summary = "Document contains information about: #{top_phrases}."
    summary += " Key entities mentioned: #{main_entities}." if main_entities.present?

    sentiment = processing_result.dig(:nlp_insights, :sentiment, :sentiment)
    summary += " Overall tone: #{sentiment}." if sentiment

    summary
  end

  def extract_search_terms(query_analysis)
    terms = []

    # Add entities as search terms
    if query_analysis[:entities]
      entities = query_analysis.dig(:entities, :entities) || []
      terms.concat(entities.map { |e| e[:text] })
    end

    # Add key phrases
    if query_analysis[:key_phrases]
      phrases = query_analysis.dig(:key_phrases, :top_phrases) || []
      terms.concat(phrases.first(3).map { |p| p[:text] })
    end

    terms.uniq
  end

  def build_search_filters(search_terms, options)
    filters = {}

    # Add entity type filters if detected
    if search_terms.any? { |term| term =~ /\d{4}/ }  # Year detected
      filters[:time_period] = 'recent'
    end

    # Add any explicit filters from options
    filters.merge!(options[:filters]) if options[:filters]

    filters
  end

  def rank_search_results(results, query_analysis)
    return results unless results && query_analysis

    sentiment = query_analysis.dig(:sentiment, :sentiment)

    # Score each result
    scored_results = results.map do |result|
      score = result[:score] || 0.5

      # Boost score if sentiment matches
      if sentiment && result[:metadata]
        doc_sentiment = result[:metadata]['sentiment']
        score *= 1.2 if doc_sentiment == sentiment.to_s
      end

      result.merge(adjusted_score: score)
    end

    # Sort by adjusted score
    scored_results.sort_by { |r| -r[:adjusted_score] }
  end

  def detect_action_items(messages)
    action_items = []
    action_keywords = ['todo', 'task', 'need to', 'must', 'should', 'will do', 'action item', 'follow up']

    messages.each do |message|
      next unless message[:role] == 'user' || message[:content].match?(/I will|I'll|We'll|Let's/)

      action_keywords.each do |keyword|
        if message[:content].downcase.include?(keyword)
          action_items << {
            message: message[:content],
            detected_keyword: keyword,
            timestamp: message[:timestamp]
          }
        end
      end
    end

    action_items
  end

  def extract_workflow_entities(entities_result)
    return {} unless entities_result&.dig(:success)

    entities_by_type = entities_result[:entities_by_type] || {}

    # Extract relevant entities for workflows
    {
      people: entities_by_type['PERSON']&.map { |e| e[:text] },
      organizations: entities_by_type['ORGANIZATION']&.map { |e| e[:text] },
      locations: entities_by_type['LOCATION']&.map { |e| e[:text] },
      dates: entities_by_type['DATE']&.map { |e| e[:text] },
      quantities: entities_by_type['QUANTITY']&.map { |e| e[:text] },
      events: entities_by_type['EVENT']&.map { |e| e[:text] }
    }.compact_blank
  end

  def determine_user_intent(key_phrases_result)
    return nil unless key_phrases_result&.dig(:success)

    phrases = key_phrases_result[:key_phrases] || []

    # Map phrases to common intents
    intent_patterns = {
      'create' => /create|build|make|generate|new/i,
      'update' => /update|edit|modify|change/i,
      'delete' => /delete|remove|cancel/i,
      'search' => /find|search|look for|where|what/i,
      'analyze' => /analyze|review|check|evaluate/i,
      'help' => /help|how to|guide|tutorial/i,
      'schedule' => /schedule|book|appointment|meeting/i,
      'send' => /send|email|message|notify/i
    }

    # Check phrases against patterns
    intent_patterns.each do |intent, pattern|
      if phrases.any? { |p| p[:text].match?(pattern) }
        return intent
      end
    end

    nil
  end

  def retrieve_session_context(entity, session_id)
    # Retrieve context from previous messages in session
    # This would query a session store or database
    {}
  end

  def track_conversation_costs(entity, message, response)
    return unless entity && response

    # Estimate tokens (rough approximation)
    input_tokens = (message.length / 4.0).ceil
    output_tokens = (response.length / 4.0).ceil

    tracker = EntityCostTracker.new(entity)
    tracker.track_scout_conversation(
      message_count: 1,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      model: 'qwen3-next-80b'
    )
  end
end