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
          
          # Update document to show we're switching to fallback
          rag_document.update!(
            docling_metadata: rag_document.docling_metadata.merge(
              'fallback_reason' => 'Docling not available'
            )
          )
          rag_document.broadcast_progress_update
          
          queue_fallback_processor(rag_document.id)
          processing_job.update!(
            status: :completed,
            completed_at: Time.current
          )
          return
        end

        # Process with Docling
        start_time = Time.current
        docling_output = process_with_docling(temp_file.path)
        processing_time_ms = ((Time.current - start_time) * 1000).to_i

        # Update document with metadata
        update_document_metadata(rag_document, docling_output)

        # Update rag_store with processing info
        rag_store.update!(
          processing_method: 'docling',
          processing_time_ms: processing_time_ms
        ) if rag_store.respond_to?(:processing_method=)

        # Queue chunking job
        Rag::ChunkingJob.perform_later(rag_document.id)

        # Mark as completed
        processing_job.update!(
          status: :completed,
          completed_at: Time.current
        )

        # Broadcast progress update
        rag_document.broadcast_progress_update

        Rails.logger.info "✅ DoclingExtractionJob: Completed in #{processing_time_ms}ms"

      rescue DoclingError => e
        Rails.logger.error "❌ Docling extraction failed: #{e.message}"

        # Try fallback processor instead
        queue_fallback_processor(rag_document.id)

        processing_job.update!(
          status: :failed,
          error_message: e.message,
          completed_at: Time.current
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
        started_at: Time.current
      )
    end

    def download_from_s3(rag_document, rag_store)
      unless rag_document.file.attached?
        raise DoclingError, "No file attached to document"
      end

      # Create temp file with correct extension
      extension = File.extname(rag_document.original_filename)
      temp_file = Tempfile.new(['document', extension])
      temp_file.binmode # Set to binary mode for binary files like PDFs

      Rails.logger.info "  Downloading file via Active Storage"

      # Download the file to the temp file
      rag_document.file.blob.download { |chunk| temp_file.write(chunk) }
      temp_file.rewind

      temp_file
    end

    def docling_available?
      # For now, always return false to use fallback processor
      # TODO: Re-enable once docling is properly installed
      return false
      
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

    def update_document_metadata(rag_document, docling_output)
      # Extract key metadata from docling output
      metadata = {
        docling_version: docling_output.dig('metadata', 'docling_version'),
        page_count: docling_output['num_pages'] || docling_output.dig('metadata', 'page_count'),
        has_tables: docling_output['tables']&.any?,
        table_count: docling_output['tables']&.length || 0,
        has_images: docling_output['images']&.any?,
        image_count: docling_output['images']&.length || 0
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
