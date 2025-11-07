class DocumentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_document, only: [:show, :edit, :update, :destroy, :download, :add_tags, :assign_subjects, :retry_processing]
  layout 'customer_admin'
  
  def index
    # Load subjects and tags for sidebar
    @subjects = current_entity.document_subjects.includes(:children).ordered
    @root_subjects = current_entity.document_subjects.roots.includes(:children).ordered
    @tags = current_entity.document_tags.popular.limit(30)
    
    # Handle search or regular listing
    if params[:q].present?
      # Use DocumentSearchService for hybrid search
      search_results = DocumentSearchService.new(current_entity).search(
        query: params[:q],
        filters: search_filters
      )
      
      @documents = search_results[:documents]
      @search_type = search_results[:search_type]
      track_search(params[:q])
    else
      # Get base documents scope
      @documents = current_entity.rag_stores
                                .includes(rag_documents: [:document_subjects, :document_tags])
                                .flat_map(&:rag_documents)
      
      # Apply filters
      @documents = filter_documents(@documents)
      
      # Sort
      @documents = sort_documents(@documents)
    end
    
    # Stats for dashboard
    @total_documents = current_entity.rag_stores.joins(:rag_documents).count('rag_documents.id')
    @total_collections = current_entity.rag_stores.count
    
    # Check if we should show grid or list view
    @view_mode = params[:view] || session[:document_view_mode] || 'grid'
    session[:document_view_mode] = @view_mode
    
    # Paginate
    @documents = Kaminari.paginate_array(@documents).page(params[:page]).per(20)
    
    respond_to do |format|
      format.html
      format.json { render json: @documents }
    end
  end
  
  def show
    @document.track_view(current_user)
    
    # Load related data
    @subjects = @document.document_subjects
    @tags = @document.document_tags
    @analytics = DocumentAnalytics.aggregate_for_document(@document)
    @related_documents = @document.find_similar_documents(limit: 5)
    @versions = @document.all_versions if @document.version > 1
    
    respond_to do |format|
      format.html
      format.json { render json: @document }
    end
  end
  
  def new
    # Form for uploading new documents
    @subjects = current_entity.document_subjects.includes(:children).ordered
    @popular_tags = current_entity.document_tags.popular.limit(10)
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
      application/vnd.ms-excel
      application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
      text/plain
      text/markdown
      text/html
      application/json
      text/csv
      application/vnd.ms-powerpoint
      application/vnd.openxmlformats-officedocument.presentationml.presentation
    ]
    
    unless allowed_types.any? { |type| uploaded_file.content_type.include?(type) }
      redirect_to new_document_path, alert: "File type not supported. Supported types: PDF, Word, Excel, PowerPoint, Text, Markdown, HTML, JSON, CSV"
      return
    end
    
    # Validate file size (max 50MB)
    if uploaded_file.size > 50.megabytes
      redirect_to new_document_path, alert: "File is too large. Maximum size is 50MB."
      return
    end
    
    begin
      # Find or create the document RAG store
      collection_name = params[:document][:collection_name].presence || "Document Library"
      Rails.logger.info "📁 Collection selected: '#{collection_name}' (param value: '#{params[:document][:collection_name]}')"
      
      rag_store = current_entity.rag_stores.find_or_create_by(
        name: collection_name,
        app_name: "documents",
        store_type: "entity"
      ) do |store|
        store.user = current_user
        store.status = 'active'
      end
      
      Rails.logger.info "📁 Using RagStore: #{rag_store.name} (ID: #{rag_store.id})"
      
      # Calculate file hash for deduplication tracking
      uploaded_file.rewind # Make sure we're at the beginning
      file_hash = Digest::SHA256.hexdigest(uploaded_file.read)
      uploaded_file.rewind # Reset for attachment
      
      # Create the document record immediately with processing status
      rag_document = rag_store.rag_documents.create!(
        original_filename: uploaded_file.original_filename,
        content_type: uploaded_file.content_type,
        file_size_bytes: uploaded_file.size,
        file_hash: file_hash,
        processing_status: 'processing',
        title: params[:document][:title].presence || uploaded_file.original_filename,
        author: params[:document][:author].presence,
        summary: params[:document][:summary].presence,
        document_date: params[:document][:document_date].presence
      )
      
      # Attach the file using Active Storage (automatically uploads to S3)
      rag_document.file.attach(uploaded_file)
      
      Rails.logger.info "✅ Document created and file attached via Active Storage!"
      
      # Cache subject_ids and tags for post-processing assignment
      if params[:document][:subject_ids].present? || params[:document][:tags].present?
        cache_key_base = "document_upload_#{rag_document.id}"
        Rails.cache.write("#{cache_key_base}_subjects", params[:document][:subject_ids], expires_in: 1.hour)
        Rails.cache.write("#{cache_key_base}_tags", params[:document][:tags], expires_in: 1.hour)
      end
      
      # Enqueue document processing job
      job = Rag::DocumentPipelineJob.perform_later(
        rag_document.id,
        auto_categorize: params[:document][:auto_categorize].present?
      )
      
      respond_to do |format|
        format.html { redirect_to document_path(rag_document), notice: "Document uploaded successfully and is being processed." }
        format.turbo_stream do
          # For quick upload, redirect to the document page using JavaScript
          render turbo_stream: turbo_stream.append("document-notifications", 
            "<script>window.location.href = '#{document_path(rag_document)}';</script>")
        end
      end
    rescue => e
      Rails.logger.error "Document upload error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # User-friendly error messages
      error_message = case e.message
      when /unknown attribute/
        "There was a configuration error. Please try again or contact support."
      when /file size/i
        "The file is too large. Maximum size is 50MB."
      when /content_type/i, /file type/i
        "This file type is not supported. Please upload PDF, Word, Excel, PowerPoint, Text, or Image files."
      else
        "An error occurred while uploading the document. Please try again."
      end
      
      respond_to do |format|
        format.html { redirect_to new_document_path, alert: error_message }
        format.turbo_stream do
          render turbo_stream: turbo_stream.prepend("document-notifications", 
            partial: "shared/notification", 
            locals: { 
              type: "error", 
              message: error_message
            }
          )
        end
      end
    end
  end
  
  def edit
    @subjects = current_entity.document_subjects.includes(:children).ordered
    @selected_subjects = @document.document_subjects
    @selected_tags = @document.document_tags
  end
  
  def update
    if @document.update(document_params)
      # Update subjects
      if params[:document][:subject_ids].present?
        subject_ids = params[:document][:subject_ids].reject(&:blank?)
        @document.document_subject_assignments.destroy_all
        @document.assign_to_subjects(subject_ids, assigned_by: current_user)
      end
      
      # Update tags
      if params[:document][:tags].present?
        tag_names = params[:document][:tags].split(',').map(&:strip)
        @document.document_tags.destroy_all
        @document.add_tags(tag_names)
      end
      
      redirect_to @document, notice: 'Document updated successfully.'
    else
      render :edit
    end
  end
  
  def destroy
    rag_store = @document.rag_store
    
    # Remove from Pinecone
    if rag_store.pinecone_namespace.present?
      begin
        pinecone_service = PineconeService.new
        chunk_ids = @document.rag_chunks.pluck(:pinecone_vector_id).compact
        pinecone_service.delete_by_ids(rag_store.pinecone_namespace, chunk_ids) if chunk_ids.any?
      rescue => e
        Rails.logger.error "Error removing from Pinecone: #{e.message}"
      end
    end
    
    # Delete document and its chunks
    begin
      @document.destroy!
      
      # If this was the last document in the store, delete the store too
      if rag_store.rag_documents.reload.count == 0
        rag_store.destroy
      end
      
      redirect_to documents_path, notice: "Document removed successfully."
    rescue ActiveRecord::RecordNotDestroyed => e
      Rails.logger.error "Failed to destroy document: #{e.message}"
      Rails.logger.error "Record errors: #{@document.errors.full_messages.join(', ')}"
      redirect_to documents_path, alert: "Cannot delete document: #{@document.errors.full_messages.join(', ')}"
    end
  rescue => e
    Rails.logger.error "Error in destroy action: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    redirect_to documents_path, alert: "Error removing document: #{e.message}"
  end
  
  def download
    @document.track_download(current_user)
    
    if @document.file.attached?
      redirect_to rails_blob_path(@document.file, disposition: "attachment"), allow_other_host: true
    else
      redirect_to documents_path, alert: "Document file not found."
    end
  end
  
  # AJAX actions
  
  def add_tags
    tag_names = params[:tags].split(',').map(&:strip)
    @document.add_tags(tag_names)
    
    render json: { success: true, tags: @document.document_tags.pluck(:name) }
  rescue => e
    render json: { success: false, error: e.message }
  end
  
  def assign_subjects
    subject_ids = params[:subject_ids]
    @document.assign_to_subjects(subject_ids, assigned_by: current_user)
    
    render json: { success: true, subjects: @document.document_subjects.pluck(:name) }
  rescue => e
    render json: { success: false, error: e.message }
  end
  
  def retry_processing
    if @document.processing_status != 'failed'
      redirect_to @document, alert: "Only failed documents can be retried."
      return
    end
    
    begin
      # Reset document status
      @document.update!(processing_status: 'processing')
      
      # Check if we have the file attached
      if @document.file.attached?
        # Re-enqueue the processing job
        Rag::DocumentPipelineJob.perform_later(
          @document.id,
          auto_categorize: false
        )
        redirect_to @document, notice: "Document processing has been restarted."
      else
        # No file attached, need to re-upload
        redirect_to new_document_path(retry_document_id: @document.id), 
                    alert: "Original file not found. Please re-upload the document."
      end
    rescue => e
      Rails.logger.error "Failed to retry document processing: #{e.message}"
      @document.update!(processing_status: 'failed')
      redirect_to @document, alert: "Failed to retry processing: #{e.message}"
    end
  end
  
  # Search endpoint
  def search
    query = params[:q]
    
    results = DocumentSearchService.new(current_entity).search(
      query: query,
      filters: search_filters
    )
    
    # Format documents for JSON response
    documents_json = results[:documents].map do |doc|
      {
        id: doc.id,
        title: doc.title,
        original_filename: doc.original_filename,
        summary: doc.summary,
        icon: doc.content_type_icon,
        processing_status: doc.processing_status,
        chunks_count: doc.chunks_count,
        view_count: doc.view_count,
        created_at: doc.created_at,
        created_at_formatted: doc.created_at.strftime("%b %d, %Y"),
        collection_name: doc.rag_store.name,
        can_retry: doc.processing_status == 'failed'
      }
    end
    
    render json: {
      success: results[:success],
      documents: documents_json,
      total_count: results[:total_count],
      search_type: results[:search_type]
    }
  end
  
  private
  
  def set_document
    @document = RagDocument.joins(:rag_store)
                          .where(rag_stores: { entity_id: current_entity.id })
                          .find(params[:id])
    @rag_store = @document.rag_store # Set @rag_store for actions that need it
  end
  
  def document_params
    params.require(:document).permit(:title, :summary, :author, :document_date)
  end
  
  def filter_documents(documents)
    # Apply subject filter
    if params[:subject_id].present?
      document_ids = DocumentSubjectAssignment.where(document_subject_id: params[:subject_id]).pluck(:rag_document_id)
      documents = documents.select { |d| document_ids.include?(d.id) }
    end
    
    # Apply tag filter  
    if params[:tags].present?
      tag_names = params[:tags].split(',')
      tagged_doc_ids = DocumentTag.joins(:document_tag_assignments)
                                  .where(entity_id: current_entity.id, name: tag_names)
                                  .pluck('document_tag_assignments.rag_document_id')
                                  .uniq
      documents = documents.select { |d| tagged_doc_ids.include?(d.id) }
    end
    
    # Apply date filter
    if params[:date_range].present?
      date_range = parse_date_range(params[:date_range])
      documents = documents.select { |d| date_range.cover?(d.created_at) }
    end
    
    # Apply content type filter
    if params[:content_type].present?
      types = params[:content_type].split(',')
      documents = documents.select do |d|
        types.any? { |t| d.content_type&.include?(t) }
      end
    end
    
    documents
  end
  
  def search_documents(documents, query)
    # For now, do a simple filename/title search
    # TODO: Integrate with full-text search or vector search
    documents.select do |d|
      d.display_title.downcase.include?(query.downcase) ||
      d.summary&.downcase&.include?(query.downcase)
    end
  end
  
  def sort_documents(documents)
    case params[:sort]
    when 'name'
      documents.sort_by(&:display_title)
    when 'views'
      documents.sort_by { |d| -d.view_count }
    when 'date_asc'
      documents.sort_by(&:created_at)
    else # default to recent
      documents.sort_by { |d| -d.created_at.to_i }
    end
  end
  
  def track_search(query)
    # TODO: Implement search tracking for analytics
    Rails.logger.info "Search performed: #{query}"
  end
  
  def search_filters
    {
      subject_id: params[:subject_id],
      tags: params[:tags],
      date_range: params[:date_range],
      content_type: params[:content_type],
      author: params[:author],
      language: params[:language]
    }.compact
  end
  
  def parse_date_range(range_string)
    case range_string
    when 'today'
      Date.current.beginning_of_day..Date.current.end_of_day
    when 'last_7_days'
      7.days.ago..Time.current
    when 'last_30_days'
      30.days.ago..Time.current
    when 'last_3_months'
      3.months.ago..Time.current
    when 'all_time'
      100.years.ago..Time.current
    else
      30.days.ago..Time.current # default
    end
  end
end
