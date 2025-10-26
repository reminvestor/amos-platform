# Fallback document processor for when Docling fails or isn't available
#
# This job uses simple extraction methods:
# - PDFs: pdf-reader gem
# - DOCX: docx gem
# - Plain text: direct file reading
#
# Creates simple text chunks without advanced structure parsing
#
# Queue: documents

module Rag
  class FallbackProcessorJob < ApplicationJob
    queue_as :documents

    retry_on StandardError, wait: :exponentially_longer, attempts: 3
    discard_on ActiveRecord::RecordNotFound

    # Simple chunking parameters
    DEFAULT_CHUNK_SIZE = 1000 # characters
    DEFAULT_OVERLAP = 100 # characters

    def perform(rag_document_id)
      rag_document = RagDocument.includes(:rag_store).find(rag_document_id)
      rag_store = rag_document.rag_store

      Rails.logger.info "📝 FallbackProcessorJob: Processing document ##{rag_document.id}"

      # Track processing
      processing_job = create_processing_job(rag_store, rag_document)

      begin
        # Download document from S3
        temp_file = download_from_s3(rag_document, rag_store)

        # Extract content based on file type
        start_time = Time.current
        content = extract_content(temp_file.path, rag_document.content_type)
        processing_time_ms = ((Time.current - start_time) * 1000).to_i

        # Create simple chunks
        chunks = create_simple_chunks(content)

        # Save chunks directly to database
        saved_chunks = save_chunks(rag_document, chunks)

        # Update metadata
        rag_document.update!(
          docling_metadata: {
            fallback: true,
            method: 'simple_extraction',
            content_length: content.length
          }
        )

        rag_store.update!(
          processing_method: 'fallback',
          processing_time_ms: processing_time_ms
        ) if rag_store.respond_to?(:processing_method=)

        # Queue embedding generation
        queue_embeddings(saved_chunks)

        # Mark as completed
        processing_job.update!(
          status: :completed,
          completed_at: Time.current,
          metadata: {
            processing_time_ms: processing_time_ms,
            chunks_created: saved_chunks.length,
            content_length: content.length
          }
        )

        Rails.logger.info "✅ FallbackProcessorJob: Created #{saved_chunks.length} chunks"

      rescue => e
        Rails.logger.error "❌ FallbackProcessorJob failed: #{e.message}"
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
        job_type: 'fallback_processor',
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

      extension = File.extname(rag_document.original_filename)
      temp_file = Tempfile.new(['document', extension])

      Rails.logger.info "  Downloading from S3: #{rag_store.s3_raw_path}"

      s3_client.get_object(
        bucket: bucket,
        key: rag_store.s3_raw_path,
        response_target: temp_file.path
      )

      temp_file
    end

    def extract_content(file_path, content_type)
      extension = File.extname(file_path).downcase

      Rails.logger.info "  Extracting content (#{extension}, #{content_type})"

      case extension
      when '.pdf'
        extract_pdf(file_path)
      when '.docx', '.doc'
        extract_docx(file_path)
      when '.txt', '.md', '.markdown'
        File.read(file_path, encoding: 'UTF-8')
      when '.html', '.htm'
        extract_html(file_path)
      else
        # Try reading as plain text
        Rails.logger.warn "  Unknown file type #{extension}, attempting plain text read"
        File.read(file_path, encoding: 'UTF-8')
      end
    rescue => e
      raise "Failed to extract content from #{File.basename(file_path)}: #{e.message}"
    end

    def extract_pdf(file_path)
      # Check if pdf-reader gem is available
      unless defined?(PDF::Reader)
        Rails.logger.warn "  pdf-reader gem not available, returning empty content"
        return "[PDF extraction requires pdf-reader gem]"
      end

      reader = PDF::Reader.new(file_path)
      text_pages = reader.pages.map(&:text)

      # Join pages with page markers
      text_pages.map.with_index do |page_text, index|
        "\n--- Page #{index + 1} ---\n#{page_text}"
      end.join("\n")

    rescue => e
      Rails.logger.error "  PDF extraction failed: #{e.message}"
      "[PDF extraction failed: #{e.message}]"
    end

    def extract_docx(file_path)
      # Check if docx gem is available
      unless defined?(Docx)
        Rails.logger.warn "  docx gem not available, returning empty content"
        return "[DOCX extraction requires docx gem]"
      end

      doc = Docx::Document.open(file_path)

      paragraphs = doc.paragraphs.map(&:text).reject(&:blank?)

      paragraphs.join("\n\n")

    rescue => e
      Rails.logger.error "  DOCX extraction failed: #{e.message}"
      "[DOCX extraction failed: #{e.message}]"
    end

    def extract_html(file_path)
      # Check if nokogiri is available
      unless defined?(Nokogiri)
        Rails.logger.warn "  nokogiri not available, reading raw HTML"
        return File.read(file_path, encoding: 'UTF-8')
      end

      html_content = File.read(file_path, encoding: 'UTF-8')
      doc = Nokogiri::HTML(html_content)

      # Remove script and style tags
      doc.css('script, style').remove

      # Extract text
      doc.text.gsub(/\s+/, ' ').strip

    rescue => e
      Rails.logger.error "  HTML extraction failed: #{e.message}"
      File.read(file_path, encoding: 'UTF-8')
    end

    def create_simple_chunks(content)
      chunks = []
      position = 0
      chunk_index = 0

      while position < content.length
        # Extract chunk with overlap
        chunk_end = [position + DEFAULT_CHUNK_SIZE, content.length].min
        chunk_text = content[position...chunk_end]

        chunks << {
          content: chunk_text.strip,
          type: 'text',
          metadata: {
            fallback: true,
            chunk_index: chunk_index,
            start_position: position,
            end_position: chunk_end
          }
        }

        # Move position forward with overlap
        position += DEFAULT_CHUNK_SIZE - DEFAULT_OVERLAP
        chunk_index += 1
      end

      Rails.logger.info "  Created #{chunks.length} simple chunks"
      chunks
    end

    def save_chunks(rag_document, chunks)
      saved_chunks = []

      chunks.each_with_index do |chunk_data, index|
        chunk = rag_document.rag_chunks.create!(
          content: chunk_data[:content],
          metadata: chunk_data[:metadata],
          chunk_index: index,
          chunk_type: chunk_data[:type] || 'text',
          token_count: (chunk_data[:content].length / 4.0).ceil
        )

        saved_chunks << chunk
      end

      # Update store chunk count
      rag_document.rag_store.update!(
        chunk_count: (rag_document.rag_store.chunk_count || 0) + saved_chunks.length
      ) if rag_document.rag_store.respond_to?(:chunk_count=)

      saved_chunks
    end

    def queue_embeddings(chunks)
      Rails.logger.info "  Queuing embedding jobs for #{chunks.length} chunks"

      # Batch size for embeddings
      batch_size = 10

      chunks.in_groups_of(batch_size, false).each_with_index do |batch, index|
        chunk_ids = batch.map(&:id)
        Rag::EmbeddingBatchJob.perform_later(chunk_ids)
      end
    end
  end
end
