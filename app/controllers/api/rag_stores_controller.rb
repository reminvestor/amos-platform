module Api
  class RagStoresController < ApplicationController
    before_action :authenticate_user!
    before_action :set_rag_store, only: [:show, :update, :destroy]

    # GET /api/rag_stores
    def index
      @rag_stores = current_entity.rag_stores.order(updated_at: :desc)
      render json: @rag_stores.map { |s| store_json(s) }
    end

    # GET /api/rag_stores/:id
    def show
      render json: store_json(@rag_store, include_documents: true)
    end

    # POST /api/rag_stores
    def create
      @rag_store = current_entity.rag_stores.build(rag_store_params)
      @rag_store.user = current_user

      if @rag_store.save
        render json: store_json(@rag_store), status: :created
      else
        render json: { error: @rag_store.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    end

    # PATCH /api/rag_stores/:id
    def update
      if @rag_store.update(rag_store_params)
        render json: store_json(@rag_store)
      else
        render json: { error: @rag_store.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    end

    # DELETE /api/rag_stores/:id
    def destroy
      @rag_store.destroy
      head :no_content
    end

    private

    def set_rag_store
      @rag_store = current_entity.rag_stores.find(params[:id])
    end

    def rag_store_params
      params.permit(:name)
    end

    def store_json(store, include_documents: false)
      json = {
        id: store.id,
        name: store.name,
        document_count: store.rag_documents.count,
        created_at: store.created_at,
        updated_at: store.updated_at
      }

      if include_documents
        json[:documents] = store.rag_documents.order(created_at: :desc).map do |doc|
          {
            id: doc.id,
            filename: doc.original_filename,
            content_type: doc.content_type,
            file_size: doc.file_size_bytes,
            created_at: doc.created_at
          }
        end
      end

      json
    end
  end
end
