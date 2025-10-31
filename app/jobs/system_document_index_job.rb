# SystemDocumentIndexJob - Index uploaded system documents into RAG
#
# This job is automatically enqueued when an admin uploads a document via
# the System Document Library UI. It orchestrates the complete indexing pipeline:
#
# Pipeline:
#   1. Download document from S3
#   2. Trigger RAG document pipeline (Docling → Chunking → Embedding)
#   3. Create system RagStore (entity_id: nil, store_type: 'system')
#   4. Link SystemDocument to RagStore
#   5. Mark as indexed
#
# Queue: documents (general processing, 3 threads)
# Retry: 3 attempts with exponential backoff
#
class SystemDocumentIndexJob < ApplicationJob
  queue_as :documents

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(system_document_id)
    system_doc = SystemDocument.find(system_document_id)

    Rails.logger.info "📚 SystemDocumentIndexJob: Processing document #{system_doc.id}"
    Rails.logger.info "   File: #{system_doc.original_filename}"
    Rails.logger.info "   Category: #{system_doc.category} → #{system_doc.subcategory}"

    # Mark as processing
    system_doc.mark_processing!

    begin
      # Step 1: Download from S3
      file_content = download_from_s3(system_doc.s3_key)

      # Step 2: Create temp file for processing
      temp_file = create_temp_file(file_content, system_doc.original_filename)

      # Step 3: Process through RAG pipeline
      #   This creates: RagStore → RagDocument → RagChunks → Embeddings
      rag_store = create_rag_store_from_document(temp_file.path, system_doc)

      # Step 4: Link SystemDocument to RagStore
      system_doc.mark_indexed!(rag_store, rag_store.rag_chunks.count)

      Rails.logger.info "✅ SystemDocumentIndexJob: Successfully indexed #{system_doc.original_filename}"
      Rails.logger.info "   RagStore ID: #{rag_store.id}"
      Rails.logger.info "   Chunks: #{rag_store.rag_chunks.count}"

    rescue => e
      Rails.logger.error "❌ SystemDocumentIndexJob failed: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")

      system_doc.mark_failed!(e)
      raise  # Re-raise to trigger retry logic
    ensure
      temp_file&.close
      temp_file&.unlink
    end
  end

  private

  def download_from_s3(s3_key)
    s3_client.get_object(
      bucket: ENV.fetch('RAG_BUCKET'),
      key: s3_key
    ).body.read
  end

  def create_temp_file(content, original_filename)
    ext = File.extname(original_filename)
    temp = Tempfile.new(['system_doc', ext])
    temp.binmode
    temp.write(content)
    temp.rewind
    temp
  end

  def create_rag_store_from_document(file_path, system_doc)
    # Create RagStore with system type
    rag_store = RagStore.create!(
      name: "#{system_doc.category.titleize} - #{system_doc.original_filename}",
      app_name: system_doc.category,
      entity: nil,  # System stores have no entity
      store_type: 'system',
      status: 'pending'
    )

    # Create RagDocument
    rag_document = RagDocument.create!(
      rag_store: rag_store,
      original_filename: system_doc.original_filename,
      file_size_bytes: system_doc.file_size_bytes,
      content_type: system_doc.content_type,
      file_hash: Digest::SHA256.file(file_path).hexdigest,
      docling_metadata: {
        category: system_doc.category,
        subcategory: system_doc.subcategory,
        uploaded_by: system_doc.uploaded_by_id,
        system_document_id: system_doc.id
      }
    )

    # Enqueue document processing pipeline
    # This will: Extract text → Chunk → Generate embeddings → Store in pgvector
    Rag::DocumentPipelineJob.perform_now(
      file_path: file_path,
      rag_store_id: rag_store.id,
      rag_document_id: rag_document.id
    )

    rag_store.reload
    rag_store
  end

  def s3_client
    @s3_client ||= Aws::S3::Client.new(
      region: ENV.fetch('AWS_REGION', 'us-east-1'),
      endpoint: ENV['AWS_S3_ENDPOINT']  # For LocalStack testing
    )
  end
end
