# Entry point for RAG document processing pipeline
#
# This job orchestrates the complete document processing flow:
# 1. Upload document to S3 (raw storage)
# 2. Create RagDocument record with file hash for deduplication
# 3. Queue DoclingExtractionJob for document parsing
#
# Flow:
#   DocumentPipelineJob → DoclingExtractionJob → ChunkingJob → EmbeddingBatchJob
#
# Queue: documents

module Rag
  class DocumentPipelineJob < ApplicationJob
    queue_as :documents

    retry_on StandardError, wait: :exponentially_longer, attempts: 3
    discard_on ActiveRecord::RecordNotFound
    discard_on ArgumentError

    def perform(rag_store_id, file_path, options = {})
      rag_store = RagStore.find(rag_store_id)

      Rails.logger.info "🚀 DocumentPipelineJob: Processing file #{file_path} for RagStore ##{rag_store_id}"

      # Update RAG store status
      start_processing!(rag_store)

      # Track processing job
      processing_job = create_processing_job(rag_store, file_path)

      begin
        # Validate file exists
        unless File.exist?(file_path)
          raise ArgumentError, "File not found: #{file_path}"
        end

        # Check for duplicates
        file_hash = calculate_file_hash(file_path)
        if duplicate_exists?(rag_store, file_hash)
          Rails.logger.warn "⚠️  Duplicate document detected (hash: #{file_hash}), skipping"
          processing_job.update!(
            status: :completed,
            completed_at: Time.current,
            metadata: { skipped: true, reason: 'duplicate' }
          )
          return
        end

        # Upload to S3
        s3_path = upload_to_s3(rag_store, file_path)

        # Create document record
        rag_document = create_document_record(rag_store, file_path, s3_path, file_hash, options)

        # Queue docling extraction
        Rag::DoclingExtractionJob.perform_later(rag_document.id)

        # Mark pipeline job as completed (extraction continues async)
        processing_job.update!(
          status: :completed,
          completed_at: Time.current,
          metadata: {
            rag_document_id: rag_document.id,
            s3_path: s3_path,
            file_size_bytes: rag_document.file_size_bytes
          }
        )

        Rails.logger.info "✅ DocumentPipelineJob: Queued extraction for #{File.basename(file_path)}"

      rescue => e
        Rails.logger.error "❌ DocumentPipelineJob failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")

        processing_job.update!(
          status: :failed,
          error_message: e.message,
          completed_at: Time.current
        )

        fail_processing!(rag_store)

        raise
      end
    end

    private

    def create_processing_job(rag_store, file_path)
      rag_store.rag_processing_jobs.create!(
        job_id: job_id,
        job_type: 'document_pipeline',
        status: :processing,
        started_at: Time.current,
        metadata: {
          filename: File.basename(file_path),
          file_size_bytes: File.size(file_path)
        }
      )
    end

    def start_processing!(rag_store)
      if rag_store.respond_to?(:start_processing!)
        rag_store.start_processing!
      elsif rag_store.respond_to?(:status=)
        rag_store.update!(status: :processing)
      end
    end

    def fail_processing!(rag_store)
      if rag_store.respond_to?(:fail_processing!)
        rag_store.fail_processing!
      elsif rag_store.respond_to?(:status=)
        rag_store.update!(status: :failed)
      end
    end

    def calculate_file_hash(file_path)
      Digest::SHA256.file(file_path).hexdigest
    end

    def duplicate_exists?(rag_store, file_hash)
      rag_store.rag_documents.exists?(file_hash: file_hash)
    end

    def upload_to_s3(rag_store, file_path)
      s3_client = Aws::S3::Client.new
      bucket = ENV.fetch('RAG_BUCKET', ENV.fetch('AWS_S3_BUCKET', 'amos-rag-storage'))

      # Generate S3 key
      s3_key = generate_s3_key(rag_store, file_path)

      Rails.logger.info "  Uploading to S3: #{bucket}/#{s3_key}"

      # Upload file
      File.open(file_path, 'rb') do |file|
        s3_client.put_object(
          bucket: bucket,
          key: s3_key,
          body: file,
          server_side_encryption: 'AES256',
          metadata: {
            'rag-store-id' => rag_store.id.to_s,
            'entity-id' => rag_store.entity_id.to_s,
            'original-filename' => File.basename(file_path),
            'uploaded-at' => Time.current.iso8601
          }
        )
      end

      # Update RAG store with S3 path
      rag_store.update!(s3_raw_path: s3_key) if rag_store.respond_to?(:s3_raw_path=)

      s3_key
    end

    def generate_s3_key(rag_store, file_path)
      filename = File.basename(file_path)
      timestamp = Time.current.strftime('%Y%m%d_%H%M%S')

      if rag_store.entity_id.present?
        # Entity-specific storage
        "entities/#{rag_store.entity_id}/raw_documents/#{rag_store.id}/#{timestamp}_#{filename}"
      else
        # System storage
        "system/#{rag_store.app_name || 'general'}/raw_documents/#{rag_store.id}/#{timestamp}_#{filename}"
      end
    end

    def create_document_record(rag_store, file_path, s3_path, file_hash, options)
      rag_store.rag_documents.create!(
        original_filename: File.basename(file_path),
        content_type: detect_content_type(file_path),
        file_size_bytes: File.size(file_path),
        file_hash: file_hash,
        docling_metadata: options[:metadata] || {}
      )
    end

    def detect_content_type(file_path)
      # Try Marcel gem first (if available)
      if defined?(Marcel)
        Marcel::MimeType.for(Pathname.new(file_path))
      else
        # Fallback to simple extension mapping
        extension = File.extname(file_path).downcase
        case extension
        when '.pdf' then 'application/pdf'
        when '.docx' then 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        when '.doc' then 'application/msword'
        when '.txt' then 'text/plain'
        when '.md', '.markdown' then 'text/markdown'
        when '.html', '.htm' then 'text/html'
        else 'application/octet-stream'
        end
      end
    end
  end
end
