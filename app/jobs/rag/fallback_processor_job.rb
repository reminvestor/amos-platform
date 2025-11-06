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

    retry_on StandardError, wait: :polynomially_longer, attempts: 3
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
        # Update status to show we're processing
        rag_document.update!(processing_status: 'processing')
        rag_document.broadcast_progress_update if rag_document.respond_to?(:broadcast_progress_update)

        content = nil
        processing_time_ms = 0
        temp_file = nil
        
        # Check if document already has extracted text (from previous partial processing)
        if rag_document.docling_metadata&.dig('extracted_text').present?
          Rails.logger.info "  Using existing extracted text from metadata"
          content = rag_document.docling_metadata['extracted_text']
          # If we have the full text, use it
          if rag_document.docling_metadata['content_length'].present?
            Rails.logger.info "  Found full extracted text (#{rag_document.docling_metadata['content_length']} chars)"
            # Try to load full text from chunks if available
            existing_chunks = rag_document.rag_chunks.order(:chunk_index)
            if existing_chunks.any?
              content = existing_chunks.map(&:content).join("\n\n")
              Rails.logger.info "  Reconstructed full text from #{existing_chunks.count} existing chunks"
            end
          end
        else
          # Download document from S3 and extract
          temp_file = download_from_s3(rag_document, rag_store)
          start_time = Time.current
          content = extract_content(temp_file.path, rag_document.content_type)
          processing_time_ms = ((Time.current - start_time) * 1000).to_i
        end

        # Check if chunks already exist
        existing_chunks = rag_document.rag_chunks
        saved_chunks = []
        
        if existing_chunks.any?
          Rails.logger.info "  Document already has #{existing_chunks.count} chunks, skipping chunk creation"
          saved_chunks = existing_chunks.to_a
        else
          # Create simple chunks
          chunks = create_simple_chunks(content)
          
          # Save chunks directly to database
          saved_chunks = save_chunks(rag_document, chunks)
        end

        # Update metadata
        rag_document.update!(
          docling_metadata: {
            fallback: true,
            method: 'simple_extraction',
            content_length: content.length,
            chunks_created: saved_chunks.length,
            extracted_text: content.truncate(1000)
          }
        )
        
        # Broadcast that we're now embedding
        rag_document.broadcast_progress_update if rag_document.respond_to?(:broadcast_progress_update)

        rag_store.update!(
          processing_method: 'fallback',
          processing_time_ms: processing_time_ms
        ) if rag_store.respond_to?(:processing_method=)

        # Queue embedding generation only for chunks without embeddings
        chunks_needing_embeddings = saved_chunks.select { |chunk| chunk.embedding.blank? }
        if chunks_needing_embeddings.any?
          Rails.logger.info "  Queuing embeddings for #{chunks_needing_embeddings.length} chunks"
          queue_embeddings(chunks_needing_embeddings)
        else
          Rails.logger.info "  All chunks already have embeddings"
          # Update document status to completed since no embedding needed
          rag_document.update!(processing_status: 'completed')
          rag_document.broadcast_progress_update if rag_document.respond_to?(:broadcast_progress_update)
        end

        # Mark as completed if processing job exists
        processing_job&.update!(
          status: :completed,
          completed_at: Time.current
        )

        Rails.logger.info "✅ FallbackProcessorJob: Created #{saved_chunks.length} chunks"

      rescue => e
        Rails.logger.error "❌ FallbackProcessorJob failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")

        processing_job&.update!(
          status: :failed,
          error_message: e.message,
          completed_at: Time.current
        )
        
        # Update document status to failed
        rag_document.update!(
          processing_status: 'failed',
          docling_metadata: rag_document.docling_metadata.merge(
            'error' => e.message,
            'failed_at' => Time.current.iso8601
          )
        )
        rag_document.broadcast_progress_update if rag_document.respond_to?(:broadcast_progress_update)

        raise

      ensure
        temp_file&.close!
      end
    end

    private

    def create_processing_job(rag_store, rag_document)
      # Try to find existing processing job or create new one
      rag_store.rag_processing_jobs.find_or_create_by!(job_id: job_id) do |job|
        job.job_type = 'fallback_processor'
        job.status = :processing
        job.started_at = Time.current
      end
    rescue ActiveRecord::RecordInvalid => e
      # If job already exists with same job_id, just return nil
      # This can happen when retrying
      Rails.logger.warn "Processing job already exists: #{e.message}"
      nil
    end

    def download_from_s3(rag_document, rag_store)
      unless rag_document.file.attached?
        raise "No file attached to document"
      end

      extension = File.extname(rag_document.original_filename)
      temp_file = Tempfile.new(['document', extension])
      temp_file.binmode # Set to binary mode for binary files like PDFs

      Rails.logger.info "  Downloading file via Active Storage"

      # Download the file to the temp file
      rag_document.file.blob.download { |chunk| temp_file.write(chunk) }
      temp_file.rewind

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

      # Note: chunk_count is calculated dynamically from associated chunks,
      # not stored as a column

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
