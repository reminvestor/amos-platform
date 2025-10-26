# Processes docling output into intelligent chunks
#
# This job:
# 1. Fetches docling JSON output from S3
# 2. Uses DoclingChunkingService for smart chunking
# 3. Creates RagChunk records in PostgreSQL
# 4. Queues EmbeddingBatchJob for each batch
#
# Queue: documents
# Depends on: DoclingExtractionJob (or FallbackProcessorJob)
# Triggers: EmbeddingBatchJob

module Rag
  class ChunkingJob < ApplicationJob
    queue_as :documents

    retry_on StandardError, wait: :exponentially_longer, attempts: 3
    discard_on ActiveRecord::RecordNotFound

    # Batch size for embedding jobs
    EMBEDDING_BATCH_SIZE = 10

    def perform(rag_document_id)
      rag_document = RagDocument.includes(:rag_store).find(rag_document_id)
      rag_store = rag_document.rag_store

      Rails.logger.info "✂️ ChunkingJob: Processing document ##{rag_document.id}"

      # Track processing
      processing_job = create_processing_job(rag_store, rag_document)

      begin
        # Load docling output
        docling_output = fetch_docling_output(rag_document, rag_store)

        # Create chunks using intelligent chunking service
        chunk_data_array = create_chunks(docling_output)

        # Save chunks to database
        chunks = save_chunks_to_database(rag_document, chunk_data_array)

        # Update document and store metadata
        update_document_metadata(rag_document, rag_store, chunks.length)

        # Queue embedding generation in batches
        queue_embedding_jobs(chunks)

        # Mark as completed
        processing_job.update!(
          status: :completed,
          completed_at: Time.current,
          metadata: { chunks_created: chunks.length }
        )

        Rails.logger.info "✅ Created #{chunks.length} chunks for document ##{rag_document.id}"

      rescue => e
        Rails.logger.error "❌ ChunkingJob failed for document ##{rag_document_id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")

        processing_job.update!(
          status: :failed,
          error_message: e.message,
          completed_at: Time.current
        )

        raise
      end
    end

    private

    def create_processing_job(rag_store, rag_document)
      rag_store.rag_processing_jobs.create!(
        job_id: job_id,
        job_type: 'chunking',
        status: :processing,
        started_at: Time.current,
        metadata: {
          rag_document_id: rag_document.id,
          filename: rag_document.original_filename
        }
      )
    end

    def fetch_docling_output(rag_document, rag_store)
      # Check if docling metadata exists
      if rag_document.docling_metadata.present?
        Rails.logger.info "  Using embedded docling metadata"
        return rag_document.docling_metadata
      end

      # Try fetching from S3
      if rag_store.s3_docling_output_path.present?
        Rails.logger.info "  Fetching docling output from S3: #{rag_store.s3_docling_output_path}"
        fetch_from_s3(rag_store.s3_docling_output_path)
      else
        raise "No docling output available for document #{rag_document.id}"
      end
    end

    def fetch_from_s3(s3_path)
      s3_client = Aws::S3::Client.new
      bucket = ENV.fetch('RAG_BUCKET', ENV.fetch('AWS_S3_BUCKET', 'amos-rag-storage'))

      response = s3_client.get_object(
        bucket: bucket,
        key: s3_path
      )

      JSON.parse(response.body.read)
    rescue Aws::S3::Errors::NoSuchKey => e
      Rails.logger.error "S3 object not found: #{s3_path}"
      raise "Docling output not found in S3: #{e.message}"
    end

    def create_chunks(docling_output)
      chunking_service = DoclingChunkingService.new(
        max_tokens: 512,
        overlap: 50,
        preserve_sections: true
      )

      chunking_service.chunk(docling_output)
    end

    def save_chunks_to_database(rag_document, chunk_data_array)
      Rails.logger.info "  Saving #{chunk_data_array.length} chunks to database"

      chunks = []

      chunk_data_array.each_with_index do |chunk_data, index|
        chunk = rag_document.rag_chunks.create!(
          content: chunk_data[:content],
          metadata: chunk_data[:metadata] || {},
          chunk_index: index,
          chunk_type: chunk_data[:type] || 'text',
          token_count: estimate_tokens(chunk_data[:content])
        )

        chunks << chunk
      end

      chunks
    end

    def update_document_metadata(rag_document, rag_store, chunk_count)
      # Update store chunk count
      current_count = rag_store.chunk_count || 0
      rag_store.update!(chunk_count: current_count + chunk_count)
    end

    def queue_embedding_jobs(chunks)
      Rails.logger.info "  Queuing embedding jobs for #{chunks.length} chunks"

      # Process in batches to avoid overwhelming the embedding API
      chunks.in_groups_of(EMBEDDING_BATCH_SIZE, false).each_with_index do |batch, index|
        chunk_ids = batch.map(&:id)

        Rails.logger.debug "    Batch #{index + 1}: #{chunk_ids.length} chunks"

        Rag::EmbeddingBatchJob.perform_later(chunk_ids)
      end
    end

    def estimate_tokens(text)
      # Rough estimate: 1 token ≈ 4 characters for English text
      # This is a heuristic; actual tokenization may differ
      (text.length / 4.0).ceil
    end
  end
end
