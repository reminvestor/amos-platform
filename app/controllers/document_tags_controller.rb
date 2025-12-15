class DocumentTagsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_document_tag, only: [:show, :edit, :update, :destroy, :merge]
  layout 'customer_admin'
  
  def index
    @tags = current_entity.document_tags.includes(:rag_documents)
    
    # Filter by category if specified
    @tags = @tags.by_category(params[:category]) if params[:category].present?
    
    # Search
    @tags = @tags.search(params[:q]) if params[:q].present?
    
    # Sort
    @tags = case params[:sort]
            when 'name'
              @tags.alphabetical
            when 'recent'
              @tags.recent
            else
              @tags.popular
            end
    
    @tags = @tags.page(params[:page]).per(50)
    
    respond_to do |format|
      format.html
      format.json { render json: @tags }
    end
  end
  
  def show
    @documents = @document_tag.rag_documents
                             .includes(:document_subjects, :document_tags)
                             .order(created_at: :desc)
                             .page(params[:page])
  end
  
  def new
    @document_tag = current_entity.document_tags.build
  end
  
  def create
    @document_tag = current_entity.document_tags.build(document_tag_params)
    
    if @document_tag.save
      redirect_to document_tags_path, notice: "Tag created successfully."
    else
      render :new
    end
  end
  
  def edit
  end
  
  def update
    if @document_tag.update(document_tag_params)
      redirect_to document_tags_path, notice: "Tag updated successfully."
    else
      render :edit
    end
  end
  
  def destroy
    @document_tag.destroy
    redirect_to document_tags_path, notice: "Tag deleted successfully."
  end
  
  def merge
    target_tag = current_entity.document_tags.find(params[:target_id])
    
    if @document_tag.merge_into(target_tag)
      redirect_to document_tags_path, notice: "Tags merged successfully."
    else
      redirect_to document_tags_path, alert: "Failed to merge tags."
    end
  end
  
  def suggest
    # SECURITY: Scope RagDocument by entity through rag_store to prevent cross-entity access
    document = if params[:document_id]
                 RagDocument.joins(:rag_store)
                            .where(rag_stores: { entity_id: current_entity.id })
                            .find_by(id: params[:document_id])
               end
    
    suggestions = if document
                    DocumentTag.suggest_for_document(document, limit: 10)
                  else
                    current_entity.document_tags.popular.limit(10)
                  end
    
    render json: suggestions.map { |tag| 
      { 
        id: tag.id, 
        name: tag.name, 
        category: tag.category,
        usage_count: tag.usage_count 
      } 
    }
  end
  
  private
  
  def set_document_tag
    @document_tag = current_entity.document_tags.find(params[:id])
  end
  
  def document_tag_params
    params.require(:document_tag).permit(:name, :category, :color)
  end
end
