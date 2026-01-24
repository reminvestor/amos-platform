module Api
  class RagDocumentsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_rag_document, only: [:show, :destroy, :download, :move]

    # GET /api/rag_documents
    def index
      scope = RagDocument.joins(:rag_store).where(rag_stores: { entity_id: current_entity.id })
      
      if params[:rag_store_id].present?
        scope = scope.where(rag_store_id: params[:rag_store_id])
      end
      
      if params[:search].present?
        scope = scope.where("original_filename ILIKE ?", "%#{params[:search]}%")
      end
      
      @documents = scope.order(created_at: :desc).limit(params[:limit] || 100)
      render json: @documents.map { |d| document_json(d) }
    end

    # GET /api/rag_documents/:id
    def show
      render json: document_json(@rag_document, include_url: true)
    end

    # POST /api/rag_documents
    def create
      rag_store = current_entity.rag_stores.find(params[:rag_store_id])
      
      file = params[:file]
      unless file
        return render json: { error: 'No file provided' }, status: :unprocessable_entity
      end

      # Calculate file hash for deduplication
      file_hash = Digest::SHA256.file(file.tempfile.path).hexdigest

      @rag_document = rag_store.rag_documents.build(
        original_filename: file.original_filename,
        content_type: file.content_type,
        file_size_bytes: file.size,
        file_hash: file_hash,
        processing_status: 'pending'
      )
      
      @rag_document.file.attach(file)

      if @rag_document.save
        # Queue processing job
        RagDocumentProcessingJob.perform_later(@rag_document.id) if defined?(RagDocumentProcessingJob)
        render json: document_json(@rag_document), status: :created
      else
        render json: { error: @rag_document.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    end

    # DELETE /api/rag_documents/:id
    def destroy
      @rag_document.destroy
      head :no_content
    end

    # GET /api/rag_documents/:id/download
    def download
      if @rag_document.file.attached?
        redirect_to @rag_document.file_download_url, allow_other_host: true
      else
        render json: { error: 'File not found' }, status: :not_found
      end
    end

    # POST /api/rag_documents/:id/move
    def move
      target_store = current_entity.rag_stores.find(params[:rag_store_id])
      
      if @rag_document.update(rag_store: target_store)
        render json: document_json(@rag_document)
      else
        render json: { error: @rag_document.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    end

    private

    def set_rag_document
      @rag_document = RagDocument.joins(:rag_store)
                                  .where(rag_stores: { entity_id: current_entity.id })
                                  .find(params[:id])
    end

    def document_json(doc, include_url: false)
      json = {
        id: doc.id,
        filename: doc.original_filename,
        content_type: doc.content_type,
        file_size: doc.file_size_bytes,
        rag_store_id: doc.rag_store_id,
        rag_store_name: doc.rag_store.name,
        processing_status: doc.processing_status,
        created_at: doc.created_at,
        updated_at: doc.updated_at
      }

      if include_url && doc.file.attached?
        json[:url] = doc.file_url
        json[:download_url] = doc.file_download_url
      end

      json
    end
  end
end
