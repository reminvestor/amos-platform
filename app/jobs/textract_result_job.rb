# app/jobs/textract_result_job.rb
class TextractResultJob < ApplicationJob
  queue_as :document_processing

  retry_on Aws::TextractService::RetryableError, wait: 30.seconds, attempts: 5
  retry_on Aws::Textract::Errors::ThrottlingException, wait: :exponentially_longer, attempts: 3

  def perform(entity_id:, job_id:, s3_key:, options: {})
    entity = Entity.find(entity_id)
    service = Aws::TextractService.new(entity)

    Rails.logger.info "Checking Textract job status: #{job_id}"

    # Check job status
    result = service.get_job_results(job_id)

    case result[:status]
    when 'completed'
      process_completed_job(entity, result, s3_key, options)
    when 'processing'
      # Re-queue to check later
      Rails.logger.info "Textract job still processing: #{result[:progress]}% complete"
      TextractResultJob.set(wait: calculate_wait_time(result[:progress])).perform_later(
        entity_id: entity_id,
        job_id: job_id,
        s3_key: s3_key,
        options: options
      )
    when 'failed'
      handle_failed_job(entity, job_id, result[:error], s3_key, options)
    end
  rescue StandardError => e
    Rails.logger.error "TextractResultJob error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    # Try fallback to Docling if configured
    if options[:fallback_to_docling] != false && ENV['OCR_FALLBACK_ENABLED'] == 'true'
      Rails.logger.info "Attempting fallback to Docling for entity #{entity_id}"
      DoclingProcessorJob.perform_later(entity_id: entity_id, s3_key: s3_key, options: options)
    else
      raise
    end
  end

  private

  def process_completed_job(entity, result, s3_key, options)
    Rails.logger.info "Textract job completed for entity #{entity.id}"

    # Find or create the RAG document
    document = find_or_create_rag_document(entity, s3_key, result)

    # Store extracted text and metadata
    document.update!(
      textract_status: 'completed',
      textract_result: result.except(:raw_text), # Store structured data
      raw_text: result[:raw_text],
      metadata: document.metadata.merge(
        textract_metadata: result[:metadata],
        pages: result[:pages].size,
        tables_count: result[:tables].size,
        forms_count: result[:forms].size,
        average_confidence: calculate_average_confidence(result)
      ),
      processed_at: Time.current
    )

    # Create chunks for RAG
    create_rag_chunks(document, result[:pages]) if options[:create_chunks] != false

    # Run Comprehend analysis if enabled
    if ENV['COMPREHEND_ENABLED'] == 'true' && options[:analyze_with_comprehend] != false
      ComprehendAnalysisJob.perform_later(document.id)
    end

    # Trigger ingestion to Bedrock KB if enabled
    if entity.use_bedrock_kb? && ENV['BEDROCK_KB_ENABLED'] == 'true'
      BedrockIngestionJob.perform_later(entity.id, document.id)
    end

    # Notify completion if callback provided
    notify_completion(entity, document, options) if options[:callback_url].present?

    document
  end

  def find_or_create_rag_document(entity, s3_key, result)
    # Extract original filename from S3 key
    original_filename = s3_key.split('/').last

    entity.rag_documents.find_or_create_by(s3_key: s3_key) do |doc|
      doc.title = original_filename
      doc.document_type = detect_document_type(original_filename, result)
      doc.source = 'textract'
      doc.status = 'processing'
    end
  end

  def create_rag_chunks(document, pages)
    Rails.logger.info "Creating RAG chunks for document #{document.id}"

    pages.each_with_index do |page, index|
      # Create chunk for each page
      chunk = document.rag_chunks.create!(
        content: page[:text],
        chunk_index: index,
        chunk_type: 'page',
        metadata: {
          page_number: page[:page_number],
          confidence: page[:average_confidence] || page[:confidence],
          lines_count: page[:lines].size,
          tables_count: page[:tables].size,
          forms_count: page[:forms].size,
          geometry: page[:geometry]
        }
      )

      # Create separate chunks for tables if present
      page[:tables].each_with_index do |table, table_index|
        document.rag_chunks.create!(
          content: format_table_as_text(table),
          chunk_index: "#{index}_table_#{table_index}",
          chunk_type: 'table',
          metadata: {
            page_number: page[:page_number],
            table_data: table[:data],
            table_dimensions: { rows: table[:rows], columns: table[:columns] },
            confidence: table[:confidence]
          }
        )
      end

      # Create separate chunks for form fields if present
      if page[:forms].present? && page[:forms].any?
        form_content = page[:forms].map { |f| "#{f[:key]}: #{f[:value]}" }.join("\n")
        document.rag_chunks.create!(
          content: form_content,
          chunk_index: "#{index}_form",
          chunk_type: 'form',
          metadata: {
            page_number: page[:page_number],
            form_fields: page[:forms],
            confidence: page[:forms].map { |f| f[:confidence] }.sum / page[:forms].size
          }
        )
      end
    end

    Rails.logger.info "Created #{document.rag_chunks.count} chunks for document #{document.id}"
  end

  def format_table_as_text(table)
    return "" unless table[:data].present?

    # Convert table data to readable text format
    lines = []
    table[:data].each_with_index do |row, i|
      lines << "Row #{i + 1}: #{row.join(' | ')}"
    end
    lines.join("\n")
  end

  def calculate_average_confidence(result)
    all_confidences = []

    result[:pages].each do |page|
      all_confidences << page[:confidence] if page[:confidence]
      all_confidences.concat(page[:confidence_scores]) if page[:confidence_scores]
    end

    return nil if all_confidences.empty?

    (all_confidences.sum / all_confidences.size).round(3)
  end

  def detect_document_type(filename, result)
    # Check filename patterns
    return 'invoice' if filename.downcase.include?('invoice')
    return 'receipt' if filename.downcase.include?('receipt')
    return 'contract' if filename.downcase.include?('contract')
    return 'form' if result[:forms].size > 5

    # Check content for document type indicators
    text = result[:raw_text].downcase
    return 'invoice' if text.include?('invoice') && text.include?('total')
    return 'receipt' if text.include?('receipt') || text.include?('payment received')
    return 'contract' if text.include?('agreement') || text.include?('terms and conditions')

    'general'
  end

  def calculate_wait_time(progress)
    # Dynamic wait time based on progress
    case progress
    when 0..25
      30.seconds
    when 26..50
      20.seconds
    when 51..75
      15.seconds
    when 76..90
      10.seconds
    else
      5.seconds
    end
  end

  def handle_failed_job(entity, job_id, error_message, s3_key, options)
    Rails.logger.error "Textract job #{job_id} failed: #{error_message}"

    # Create or update document with failure status
    document = entity.rag_documents.find_or_create_by(s3_key: s3_key) do |doc|
      doc.title = s3_key.split('/').last
      doc.source = 'textract'
    end

    document.update!(
      textract_status: 'failed',
      error_message: error_message,
      status: 'failed'
    )

    # Notify entity admin if configured
    if entity.notify_on_ocr_failure?
      EntityMailer.document_processing_failed(
        entity,
        job_id,
        error_message
      ).deliver_later
    end

    # Try Docling fallback if enabled
    if ENV['OCR_FALLBACK_ENABLED'] == 'true' && options[:fallback_to_docling] != false
      Rails.logger.info "Attempting Docling fallback for failed Textract job"
      DoclingProcessorJob.perform_later(
        entity_id: entity.id,
        s3_key: s3_key,
        options: options.merge(textract_failed: true)
      )
    end
  end

  def notify_completion(entity, document, options)
    return unless options[:callback_url].present?

    # Send webhook notification
    NotificationWebhookJob.perform_later(
      url: options[:callback_url],
      payload: {
        event: 'document.processed',
        entity_id: entity.id,
        document_id: document.id,
        status: 'completed',
        provider: 'textract',
        metadata: {
          pages: document.metadata['pages'],
          confidence: document.metadata['average_confidence'],
          processing_time_seconds: options[:processing_start_time] ?
            (Time.current - Time.parse(options[:processing_start_time])).to_i : nil
        }
      }
    )
  rescue => e
    Rails.logger.error "Failed to send completion notification: #{e.message}"
  end
end