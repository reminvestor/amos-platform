# Entry point for RAG document processing pipeline
#
# This job orchestrates the complete document processing flow:
# 1. Document already has file attached via Active Storage 
# 2. Queue DoclingExtractionJob for document parsing
#
# Flow:
#   DocumentPipelineJob → DoclingExtractionJob → ChunkingJob → EmbeddingBatchJob
#
# Queue: documents

module Rag
  class DocumentPipelineJob < ApplicationJob
    queue_as :documents

    retry_on StandardError, wait: :polynomially_longer, attempts: 3
    discard_on ActiveRecord::RecordNotFound

    def perform(document_id, options = {})
      document = RagDocument.find(document_id)
      rag_store = document.rag_store

      Rails.logger.info "🚀 DocumentPipelineJob: Processing document ##{document_id} for RagStore ##{rag_store.id}"

      # Track processing job
      processing_job = create_processing_job(rag_store, document)

      begin
        # Validate file exists
        unless document.file.attached?
          raise ArgumentError, "No file attached to document ##{document_id}"
        end
        
        # Apply any pending subject/tag assignments from upload
        apply_pending_assignments(document)
        
        # Auto-categorize if requested
        if options[:auto_categorize]
          DocumentCategorizationService.new(rag_store.entity).categorize(document)
        end

        # Queue extraction job
        Rag::DoclingExtractionJob.perform_later(document.id)

        # Mark pipeline job as completed (extraction continues async)
        processing_job.update!(
          status: :completed,
          completed_at: Time.current
        )

        Rails.logger.info "✅ DocumentPipelineJob: Queued extraction for document ##{document_id}"

      rescue => e
        Rails.logger.error "❌ DocumentPipelineJob failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")

        processing_job&.update!(
          status: :failed,
          error_message: e.message,
          completed_at: Time.current
        )

        document.update!(processing_status: 'failed')
        raise
      end
    end

    private

    def create_processing_job(rag_store, document)
      rag_store.rag_processing_jobs.create!(
        job_id: job_id,
        job_type: 'pipeline',
        status: :processing,
        started_at: Time.current
      )
    end
    
    def apply_pending_assignments(document)
      cache_key_base = "document_upload_#{document.id}"
      
      # Apply subjects
      subject_ids = Rails.cache.read("#{cache_key_base}_subjects")
      if subject_ids.present?
        document.assign_to_subjects(subject_ids)
        Rails.cache.delete("#{cache_key_base}_subjects")
      end
      
      # Apply tags
      tags = Rails.cache.read("#{cache_key_base}_tags")
      if tags.present?
        document.add_tags(tags)
        Rails.cache.delete("#{cache_key_base}_tags")
      end
    end
  end
end