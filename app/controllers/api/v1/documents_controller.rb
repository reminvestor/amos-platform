# frozen_string_literal: true

module Api
  module V1
    class DocumentsController < BaseController
      before_action :set_document, only: [:show, :destroy]

      # GET /api/v1/documents
      def index
        # Get all documents for the entity through rag_stores
        @documents = RagDocument
                       .for_entity(current_entity)
                       .includes(:rag_store, :document_tags, :document_subjects)
                       .recent
                       .page(params[:page] || 1)
                       .per(params[:per_page] || 50)

        # Apply search filter
        if params[:search].present?
          @documents = @documents.where(
            "original_filename ILIKE ? OR title ILIKE ?",
            "%#{params[:search]}%",
            "%#{params[:search]}%"
          )
        end

        # Filter by content type
        if params[:content_type].present?
          @documents = @documents.where("content_type LIKE ?", "%#{params[:content_type]}%")
        end

        # Filter by status
        if params[:status].present?
          @documents = @documents.where(processing_status: params[:status])
        end

        render json: {
          data: @documents.map { |d| document_json(d) },
          meta: {
            current_page: @documents.current_page,
            total_pages: @documents.total_pages,
            total_count: @documents.total_count
          }
        }
      end

      # GET /api/v1/documents/:id
      def show
        render json: document_json(@document, detailed: true)
      end

      # GET /api/v1/documents/collections
      def collections
        @rag_stores = current_entity.rag_stores
                                    .includes(:rag_documents)
                                    .order(created_at: :desc)

        render json: {
          data: @rag_stores.map { |store| collection_json(store) }
        }
      end

      # POST /api/v1/documents
      # Upload a new document
      def create
        unless params[:file].present?
          render json: { error: "Please provide a file" }, status: :unprocessable_entity
          return
        end

        uploaded_file = params[:file]

        # Validate file type
        allowed_types = %w[
          application/pdf
          application/msword
          application/vnd.openxmlformats-officedocument.wordprocessingml.document
          application/vnd.ms-excel
          application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
          text/plain
          text/markdown
          text/html
          application/json
          text/csv
          image/png
          image/jpeg
        ]

        unless allowed_types.any? { |type| uploaded_file.content_type.to_s.include?(type.split('/').last) }
          render json: { error: "File type not supported" }, status: :unprocessable_entity
          return
        end

        # Find or create default RAG store for entity
        @rag_store = current_entity.rag_stores.find_or_create_by!(
          name: "Knowledge Base",
          app_name: "amos",
          store_type: "entity",
          user: current_user
        ) do |store|
          store.status = "active"
        end

        # Calculate file hash
        file_hash = Digest::SHA256.file(uploaded_file.tempfile.path).hexdigest

        # Create document
        @document = @rag_store.rag_documents.create!(
          original_filename: uploaded_file.original_filename,
          content_type: uploaded_file.content_type,
          file_size_bytes: uploaded_file.size,
          file_hash: file_hash,
          processing_status: "pending",
          is_latest_version: true,
          version: 1
        )

        # Attach file
        @document.file.attach(uploaded_file)

        # Trigger processing job (if exists)
        begin
          ProcessDocumentJob.perform_later(@document.id) if defined?(ProcessDocumentJob)
        rescue StandardError => e
          Rails.logger.warn("Could not queue document processing: #{e.message}")
        end

        render json: {
          success: true,
          document: document_json(@document)
        }, status: :created
      end

      # DELETE /api/v1/documents/:id
      def destroy
        @document.destroy
        render json: { success: true }
      end

      # GET /api/v1/documents/:id/status
      def status
        @document = RagDocument.for_entity(current_entity).find(params[:id])

        render json: {
          id: @document.id,
          processing_status: @document.processing_status,
          processing_stage: @document.processing_stage,
          processing_stage_description: @document.processing_stage_description,
          processing_progress: @document.processing_progress,
          chunks_count: @document.chunks_count,
          embedded_chunks_count: @document.embedded_chunks_count
        }
      end

      private

      def set_document
        @document = RagDocument.for_entity(current_entity).find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Document not found" }, status: :not_found
      end

      def document_json(document, detailed: false)
        json = {
          id: document.id,
          filename: document.original_filename,
          title: document.display_title,
          content_type: document.content_type,
          file_size: document.file_size_human,
          file_size_bytes: document.file_size_bytes,
          processing_status: document.processing_status,
          processing_progress: document.processing_progress,
          chunks_count: document.chunks_count,
          view_count: document.view_count,
          download_count: document.download_count,
          collection_name: document.rag_store.name,
          collection_id: document.rag_store_id,
          icon: document.content_type_icon,
          created_at: document.created_at,
          updated_at: document.updated_at
        }

        if detailed
          json.merge!(
            processing_stage: document.processing_stage,
            processing_stage_description: document.processing_stage_description,
            embedded_chunks_count: document.embedded_chunks_count,
            tags: document.document_tags.map { |t| { id: t.id, name: t.name } },
            subjects: document.document_subjects.map { |s| { id: s.id, name: s.name } },
            has_tables: document.has_extracted_tables?,
            has_images: document.has_extracted_images?,
            author: document.author,
            language: document.language,
            version: document.version,
            last_accessed_at: document.last_accessed_at
          )
        end

        json
      end

      def collection_json(store)
        {
          id: store.id,
          name: store.name,
          status: store.status,
          document_count: store.document_count,
          chunk_count: store.chunk_count,
          created_at: store.created_at,
          updated_at: store.updated_at
        }
      end
    end
  end
end
