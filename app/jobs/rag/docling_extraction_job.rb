# Extracts content from documents using Docling Python library
#
# This job:
# 1. Downloads document from S3 to temp file
# 2. Runs Docling CLI to extract text, tables, structure
# 3. Stores Docling JSON output in S3
# 4. Updates RagDocument with metadata
# 5. Queues ChunkingJob
#
# Falls back to FallbackProcessorJob on failure
#
# Queue: docling (memory-intensive, limited concurrency)

module Rag
  class DoclingExtractionJob < ApplicationJob
    queue_as :docling

    # Custom error class
    class DoclingError < StandardError; end

    # Docling can fail for various reasons - retry twice then fallback
    retry_on StandardError, wait: 30.seconds, attempts: 2
    retry_on DoclingError, wait: 1.minute, attempts: 1

    discard_on ActiveRecord::RecordNotFound

    # Docling timeout (large documents can take minutes)
    DOCLING_TIMEOUT = 10.minutes

    def perform(rag_document_id)
      rag_document = RagDocument.includes(:rag_store).find(rag_document_id)
      rag_store = rag_document.rag_store

      Rails.logger.info "🔬 DoclingExtractionJob: Processing document ##{rag_document.id}"

      # Track processing
      processing_job = create_processing_job(rag_store, rag_document)

      begin
        # Download document from S3
        temp_file = download_from_s3(rag_document, rag_store)

        # Check if docling is available
        unless docling_available?
          Rails.logger.warn "⚠️  Docling not available, using fallback processor"
          queue_fallback_processor(rag_document.id)
          processing_job.update!(
            status: :completed,
            completed_at: Time.current,
            metadata: { fallback: true, reason: 'docling_unavailable' }
          )
          return
        end

        # Process with Docling
        start_time = Time.current
        docling_output = process_with_docling(temp_file.path)
        processing_time_ms = ((Time.current - start_time) * 1000).to_i

        # Store docling output in S3
        docling_s3_path = store_docling_output(rag_store, rag_document, docling_output)

        # Update document with metadata
        update_document_metadata(rag_document, docling_output, docling_s3_path)

        # Update rag_store with processing info
        rag_store.update!(
          processing_method: 'docling',
          processing_time_ms: processing_time_ms,
          s3_docling_output_path: docling_s3_path
        ) if rag_store.respond_to?(:processing_method=)

        # Queue chunking job
        Rag::ChunkingJob.perform_later(rag_document.id)

        # Mark as completed
        processing_job.update!(
          status: :completed,
          completed_at: Time.current,
          metadata: {
            processing_time_ms: processing_time_ms,
            page_count: docling_output.dig('metadata', 'page_count') || docling_output['num_pages']
          }
        )

        Rails.logger.info "✅ DoclingExtractionJob: Completed in #{processing_time_ms}ms"

      rescue DoclingError => e
        Rails.logger.error "❌ Docling extraction failed: #{e.message}"

        # Try fallback processor instead
        queue_fallback_processor(rag_document.id)

        processing_job.update!(
          status: :failed,
          error_message: e.message,
          completed_at: Time.current,
          metadata: { fallback_queued: true }
        )

      rescue => e
        Rails.logger.error "❌ DoclingExtractionJob failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")

        processing_job.update!(
          status: :failed,
          error_message: e.message,
          completed_at: Time.current
        )

        raise

      ensure
        temp_file&.close!
      end
    end

    private

    def create_processing_job(rag_store, rag_document)
      rag_store.rag_processing_jobs.create!(
        job_id: job_id,
        job_type: 'docling_extraction',
        status: :processing,
        started_at: Time.current,
        metadata: {
          rag_document_id: rag_document.id,
          filename: rag_document.original_filename
        }
      )
    end

    def download_from_s3(rag_document, rag_store)
      s3_client = Aws::S3::Client.new
      bucket = ENV.fetch('RAG_BUCKET', ENV.fetch('AWS_S3_BUCKET', 'amos-rag-storage'))

      # Create temp file with correct extension
      extension = File.extname(rag_document.original_filename)
      temp_file = Tempfile.new(['document', extension])

      Rails.logger.info "  Downloading from S3: #{rag_store.s3_raw_path}"

      s3_client.get_object(
        bucket: bucket,
        key: rag_store.s3_raw_path,
        response_target: temp_file.path
      )

      temp_file
    rescue Aws::S3::Errors::NoSuchKey => e
      raise DoclingError, "Document not found in S3: #{e.message}"
    end

    def docling_available?
      # Check if DoclingBridgeService exists and is available
      if defined?(DoclingBridgeService)
        DoclingBridgeService.available?
      else
        # Fallback: check if docling command exists
        system('which docling > /dev/null 2>&1') || system('python3 -c "import docling" 2>/dev/null')
      end
    end

    def process_with_docling(file_path)
      Rails.logger.info "  Running Docling on #{File.basename(file_path)}"

      # Use DoclingBridgeService if available
      if defined?(DoclingBridgeService) && DoclingBridgeService.available?
        return DoclingBridgeService.process_document(file_path)
      end

      # Fallback to direct CLI invocation
      cmd = build_docling_command(file_path)

      output, status = nil, nil

      # Run with timeout
      Timeout.timeout(DOCLING_TIMEOUT) do
        output, status = Open3.capture2e(cmd)
      end

      unless status.success?
        raise DoclingError, "Docling command failed: #{output}"
      end

      # Parse JSON output
      parsed = JSON.parse(output)

      # Validate output structure
      unless parsed.is_a?(Hash)
        raise DoclingError, "Invalid docling output: expected Hash, got #{parsed.class}"
      end

      parsed

    rescue JSON::ParserError => e
      raise DoclingError, "Invalid JSON from docling: #{e.message}"
    rescue Timeout::Error
      raise DoclingError, "Docling timed out after #{DOCLING_TIMEOUT} seconds"
    end

    def build_docling_command(file_path)
      # Docling CLI command with options
      options = [
        'docling',
        '--format json',
        '--extract-tables',
        '--extract-images',
        '--preserve-formatting',
        Shellwords.escape(file_path)
      ]

      options.join(' ')
    end

    def store_docling_output(rag_store, rag_document, output)
      s3_client = Aws::S3::Client.new
      bucket = ENV.fetch('RAG_BUCKET', ENV.fetch('AWS_S3_BUCKET', 'amos-rag-storage'))

      # Generate S3 key for docling output
      s3_key = generate_docling_s3_key(rag_store, rag_document)

      Rails.logger.info "  Storing docling output in S3: #{s3_key}"

      s3_client.put_object(
        bucket: bucket,
        key: s3_key,
        body: output.to_json,
        content_type: 'application/json',
        server_side_encryption: 'AES256',
        metadata: {
          'rag-document-id' => rag_document.id.to_s,
          'generated-at' => Time.current.iso8601
        }
      )

      s3_key
    end

    def generate_docling_s3_key(rag_store, rag_document)
      if rag_store.entity_id.present?
        "entities/#{rag_store.entity_id}/docling_output/#{rag_store.id}/#{rag_document.id}_output.json"
      else
        "system/#{rag_store.app_name || 'general'}/docling_output/#{rag_store.id}/#{rag_document.id}_output.json"
      end
    end

    def update_document_metadata(rag_document, docling_output, docling_s3_path)
      # Extract key metadata from docling output
      metadata = {
        docling_version: docling_output.dig('metadata', 'docling_version'),
        page_count: docling_output['num_pages'] || docling_output.dig('metadata', 'page_count'),
        has_tables: docling_output['tables']&.any?,
        table_count: docling_output['tables']&.length || 0,
        has_images: docling_output['images']&.any?,
        image_count: docling_output['images']&.length || 0,
        s3_path: docling_s3_path
      }

      rag_document.update!(
        docling_metadata: metadata,
        page_count: metadata[:page_count],
        extracted_tables: docling_output['tables'] || []
      )
    end

    def queue_fallback_processor(rag_document_id)
      Rails.logger.info "  Queuing fallback processor for document ##{rag_document_id}"
      Rag::FallbackProcessorJob.perform_later(rag_document_id)
    end
  end
end
