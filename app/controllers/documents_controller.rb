class DocumentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_rag_store, only: [:destroy, :download]
  layout 'customer_admin'
  
  def index
    # Show all RAG documents for this entity
    @rag_stores = current_entity.rag_stores
      .includes(:rag_documents)
      .order(created_at: :desc)
    
    # Flatten all documents from all stores
    @documents = RagDocument.joins(:rag_store)
      .where(rag_stores: { entity_id: current_entity.id })
      .order(created_at: :desc)
  end
  
  def new
    # Form for uploading new documents
  end
  
  def create
    uploaded_file = params[:document][:file]
    
    unless uploaded_file
      redirect_to new_document_path, alert: "Please select a file to upload."
      return
    end
    
    # Validate file type
    allowed_types = %w[
      application/pdf 
      application/msword 
      application/vnd.openxmlformats-officedocument.wordprocessingml.document
      text/plain
      text/markdown
      text/html
      application/json
      text/csv
    ]
    
    unless allowed_types.include?(uploaded_file.content_type)
      redirect_to new_document_path, alert: "File type not supported. Supported types: PDF, Word, Text, Markdown, HTML, JSON, CSV"
      return
    end
    
    # Validate file size (max 50MB)
    if uploaded_file.size > 50.megabytes
      redirect_to new_document_path, alert: "File is too large. Maximum size is 50MB."
      return
    end
    
    begin
      # Find or create the document RAG store
      rag_store = current_entity.rag_stores.find_or_create_by(
        name: params[:document][:collection_name].presence || "Document Library",
        app_name: "documents",
        store_type: "entity"
      ) do |store|
        store.user = current_user
        store.status = 'active'
      end
      
      # Create a temp file for processing
      temp_file = Tempfile.new(['document', File.extname(uploaded_file.original_filename)])
      temp_file.binmode
      temp_file.write(uploaded_file.read)
      temp_file.rewind
      
      # Enqueue document processing job
      Rag::DocumentPipelineJob.perform_later(
        rag_store.id,
        temp_file.path,
        {
          source: "document_library",
          original_filename: uploaded_file.original_filename,
          content_type: uploaded_file.content_type,
          user_id: current_user.id
        }
      )
      
      redirect_to documents_path, notice: "Document uploaded successfully. It will be processed in the background."
    rescue => e
      Rails.logger.error "Document upload error: #{e.message}"
      redirect_to new_document_path, alert: "Error uploading document: #{e.message}"
    end
  end
  
  def destroy
    @document = @rag_store.rag_documents.find(params[:id])
    
    # Remove from Pinecone
    if @rag_store.pinecone_namespace.present?
      pinecone_service = PineconeService.new
      chunk_ids = @document.rag_chunks.pluck(:id).map(&:to_s)
      pinecone_service.delete_by_ids(@rag_store.pinecone_namespace, chunk_ids) if chunk_ids.any?
    end
    
    # Delete document and its chunks
    @document.destroy
    
    # If this was the last document in the store, delete the store too
    if @rag_store.rag_documents.count == 0
      @rag_store.destroy
    end
    
    redirect_to documents_path, notice: "Document removed successfully."
  rescue => e
    redirect_to documents_path, alert: "Error removing document: #{e.message}"
  end
  
  def download
    @document = @rag_store.rag_documents.find(params[:id])
    
    # If we have the S3 key, redirect to a presigned URL
    if @document.s3_key.present?
      s3_service = AwsS3Service.new
      presigned_url = s3_service.presigned_url(@document.s3_key, expires_in: 300)
      redirect_to presigned_url, allow_other_host: true
    else
      redirect_to documents_path, alert: "Original file not available."
    end
  rescue => e
    redirect_to documents_path, alert: "Error downloading document: #{e.message}"
  end
  
  private
  
  def set_rag_store
    @rag_store = current_entity.rag_stores.find_by!(id: params[:rag_store_id] || RagDocument.find(params[:id]).rag_store_id)
  end
end
