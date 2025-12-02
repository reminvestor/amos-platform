# app/services/document_processor_v2.rb
# Enhanced Document Processor with AWS Bedrock Integration
class DocumentProcessorV2
  include Singleton

  attr_reader :ocr_service, :kb_service, :comprehend_service

  def initialize
    @ocr_service = Ocr::DualModeService.instance
    @kb_service = Aws::BedrockKnowledgeBaseService.instance
    @comprehend_service = Aws::ComprehendService.instance
    @cost_calculator = Aws::CostCalculator.new
  end

  # Main entry point for processing documents
  def process_document(entity, file_path, options = {})
    Rails.logger.info "Processing document for entity #{entity.id}: #{file_path}"

    # Initialize processing result
    result = {
      file_path: file_path,
      file_name: File.basename(file_path),
      file_size: File.size(file_path),
      started_at: Time.current,
      steps: []
    }

    begin
      # Step 1: OCR Processing (if needed)
      if needs_ocr?(file_path)
        ocr_result = perform_ocr(entity, file_path, options)
        result[:steps] << { step: 'ocr', status: ocr_result[:success] ? 'completed' : 'failed', data: ocr_result }
        result[:extracted_text] = ocr_result[:text] if ocr_result[:success]
      else
        # Extract text directly for text-based files
        result[:extracted_text] = extract_text_content(file_path)
        result[:steps] << { step: 'text_extraction', status: 'completed' }
      end

      # Step 2: NLP Analysis with Comprehend
      if result[:extracted_text] && options[:enable_nlp] != false
        nlp_result = perform_nlp_analysis(entity, result[:extracted_text], options)
        result[:steps] << { step: 'nlp_analysis', status: 'completed', data: nlp_result }
        result[:nlp_insights] = nlp_result
      end

      # Step 3: Add to Bedrock Knowledge Base
      kb_result = add_to_knowledge_base(entity, file_path, result, options)
      result[:steps] << { step: 'knowledge_base', status: kb_result[:success] ? 'completed' : 'failed', data: kb_result }

      # Step 4: Create or update RAG document record
      rag_doc = create_rag_document(entity, file_path, result, options)
      result[:rag_document_id] = rag_doc.id

      # Calculate and track costs
      track_processing_costs(entity, result)

      result[:success] = true
      result[:completed_at] = Time.current
      result[:processing_time] = result[:completed_at] - result[:started_at]

      Rails.logger.info "Successfully processed document #{file_path} in #{result[:processing_time]}s"

    rescue => e
      Rails.logger.error "Document processing failed: #{e.message}\n#{e.backtrace.join("\n")}"
      result[:success] = false
      result[:error] = e.message
    end

    result
  end

  # Batch process multiple documents
  def process_batch(entity, file_paths, options = {})
    results = []

    file_paths.each_with_index do |file_path, index|
      Rails.logger.info "Processing document #{index + 1}/#{file_paths.count}"

      result = process_document(entity, file_path, options)
      results << result

      # Add delay to avoid rate limiting
      sleep(0.5) if file_paths.count > 10
    end

    # Trigger KB sync after batch processing
    @kb_service.start_ingestion_job(entity.bedrock_knowledge_base_id, entity) if entity.bedrock_knowledge_base_id

    {
      total: file_paths.count,
      successful: results.count { |r| r[:success] },
      failed: results.count { |r| !r[:success] },
      results: results
    }
  end

  # Query the knowledge base
  def query_knowledge(entity, query, options = {})
    # Use Bedrock KB for retrieval
    kb_results = @kb_service.query(entity, query, options)

    # If requested, also perform semantic analysis on the query
    if options[:analyze_query]
      query_analysis = @comprehend_service.analyze_text(query, entity: entity)
      kb_results[:query_analysis] = query_analysis
    end

    kb_results
  end

  # Generate answer using RAG
  def generate_answer(entity, query, session_id = nil, options = {})
    # Use Bedrock's retrieve_and_generate for complete RAG flow
    result = @kb_service.retrieve_and_generate(entity, query, session_id, options)

    # Track usage for cost monitoring
    track_query_costs(entity, query, result)

    result
  end

  private

  def needs_ocr?(file_path)
    # Check if file type requires OCR
    extension = File.extname(file_path).downcase
    mime_type = Marcel::MimeType.for(file_path)

    ocr_extensions = ['.pdf', '.png', '.jpg', '.jpeg', '.tiff', '.bmp']
    ocr_mime_types = ['application/pdf', 'image/png', 'image/jpeg', 'image/tiff', 'image/bmp']

    ocr_extensions.include?(extension) || ocr_mime_types.include?(mime_type)
  end

  def perform_ocr(entity, file_path, options)
    Rails.logger.info "Performing OCR on #{file_path}"

    # Use dual-mode OCR service
    ocr_options = options.merge(
      entity: entity,
      track_costs: true,
      enable_tables: options[:extract_tables],
      enable_forms: options[:extract_forms]
    )

    @ocr_service.process(file_path, ocr_options)
  end

  def extract_text_content(file_path)
    # Extract text from text-based files
    extension = File.extname(file_path).downcase

    case extension
    when '.txt', '.md', '.markdown'
      File.read(file_path)
    when '.json'
      JSON.parse(File.read(file_path)).to_s
    when '.csv'
      require 'csv'
      CSV.read(file_path).map(&:to_csv).join
    when '.html', '.htm'
      require 'nokogiri'
      doc = Nokogiri::HTML(File.read(file_path))
      doc.text.squeeze(' ').strip
    when '.xml'
      require 'nokogiri'
      doc = Nokogiri::XML(File.read(file_path))
      doc.text.squeeze(' ').strip
    else
      # Try to read as plain text
      File.read(file_path)
    end
  rescue => e
    Rails.logger.error "Failed to extract text from #{file_path}: #{e.message}"
    nil
  end

  def perform_nlp_analysis(entity, text, options)
    Rails.logger.info "Performing NLP analysis"

    analysis = {}

    # Limit text size for NLP (Comprehend has limits)
    truncated_text = text[0..50000]  # First 50k chars

    # Detect entities
    if options[:detect_entities] != false
      entities = @comprehend_service.detect_entities(truncated_text, entity: entity)
      analysis[:entities] = entities[:entities] if entities[:success]
    end

    # Detect key phrases
    if options[:detect_key_phrases] != false
      key_phrases = @comprehend_service.detect_key_phrases(truncated_text, entity: entity)
      analysis[:key_phrases] = key_phrases[:key_phrases] if key_phrases[:success]
    end

    # Detect sentiment
    if options[:detect_sentiment] != false
      sentiment = @comprehend_service.detect_sentiment(truncated_text, entity: entity)
      analysis[:sentiment] = sentiment[:sentiment] if sentiment[:success]
    end

    # Detect PII for compliance
    if options[:detect_pii]
      pii = @comprehend_service.detect_pii(truncated_text, entity: entity)
      analysis[:pii_entities] = pii[:entities] if pii[:success]
    end

    # Detect language
    language = @comprehend_service.detect_language(truncated_text, entity: entity)
    analysis[:language] = language[:languages]&.first if language[:success]

    analysis
  rescue => e
    Rails.logger.error "NLP analysis failed: #{e.message}"
    {}
  end

  def add_to_knowledge_base(entity, file_path, processing_result, options)
    Rails.logger.info "Adding to Bedrock Knowledge Base"

    # Prepare metadata
    metadata = {
      file_name: processing_result[:file_name],
      file_size: processing_result[:file_size],
      processing_date: Time.current.iso8601,
      content_type: Marcel::MimeType.for(file_path)
    }

    # Add NLP insights to metadata if available
    if processing_result[:nlp_insights]
      metadata[:language] = processing_result[:nlp_insights][:language][:language_code] if processing_result[:nlp_insights][:language]
      metadata[:sentiment] = processing_result[:nlp_insights][:sentiment] if processing_result[:nlp_insights][:sentiment]

      # Add top entities and key phrases
      if processing_result[:nlp_insights][:entities]
        top_entities = processing_result[:nlp_insights][:entities]
          .select { |e| e[:score] > 0.8 }
          .first(5)
          .map { |e| "#{e[:type]}:#{e[:text]}" }
        metadata[:entities] = top_entities.join(',') if top_entities.any?
      end

      if processing_result[:nlp_insights][:key_phrases]
        top_phrases = processing_result[:nlp_insights][:key_phrases]
          .select { |p| p[:score] > 0.9 }
          .first(5)
          .map { |p| p[:text] }
        metadata[:key_phrases] = top_phrases.join(',') if top_phrases.any?
      end
    end

    # Add custom metadata from options
    metadata.merge!(options[:metadata]) if options[:metadata]

    # Add document to KB
    @kb_service.add_document(entity, file_path, metadata)
  end

  def create_rag_document(entity, file_path, processing_result, options)
    # Create or update RAG document record
    doc = entity.rag_documents.find_or_initialize_by(
      file_path: file_path
    )

    doc.assign_attributes(
      file_name: processing_result[:file_name],
      file_size_bytes: processing_result[:file_size],
      content_type: Marcel::MimeType.for(file_path),
      processing_status: processing_result[:success] ? 'completed' : 'failed',
      provider: 'bedrock',
      metadata: {
        processing_result: processing_result,
        nlp_insights: processing_result[:nlp_insights],
        kb_metadata: processing_result.dig(:steps, -1, :data),
        processed_at: Time.current.iso8601
      }.merge(options[:metadata] || {})
    )

    # Store extracted text if available
    doc.content = processing_result[:extracted_text] if processing_result[:extracted_text]

    doc.save!
    doc
  end

  def track_processing_costs(entity, result)
    tracker = EntityCostTracker.new(entity)

    # Track OCR costs if OCR was performed
    ocr_step = result[:steps].find { |s| s[:step] == 'ocr' }
    if ocr_step && ocr_step[:data]
      # OCR costs are already tracked by the OCR service
    end

    # Track NLP costs
    if result[:nlp_insights]
      text_length = result[:extracted_text]&.length || 0

      # Track each Comprehend operation
      tracker.track_usage(
        category: :analytics,
        service: :comprehend,
        usage_type: :nlp_analysis,
        quantity: (text_length / 100.0).ceil,  # Comprehend charges per 100 chars
        metadata: {
          operations: result[:nlp_insights].keys,
          document: result[:file_name]
        }
      )
    end

    # Track KB ingestion costs
    file_size_gb = result[:file_size].to_f / 1.gigabyte
    tracker.track_usage(
      category: :search,
      service: :bedrock_kb_ingestion,
      usage_type: :per_gb,
      quantity: file_size_gb,
      metadata: {
        document: result[:file_name]
      }
    )

    # Track S3 storage costs
    tracker.track_usage(
      category: :storage,
      service: :s3_standard,
      usage_type: :per_gb_month,
      quantity: file_size_gb,
      metadata: {
        document: result[:file_name]
      }
    )
  end

  def track_query_costs(entity, query, result)
    tracker = EntityCostTracker.new(entity)

    # Query costs are tracked by the KB service
    # Here we just log for monitoring
    Rails.logger.info "Query processed for entity #{entity.id}: #{query[0..50]}..."
  end
end