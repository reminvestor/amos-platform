# Admin::SystemDocumentsController - Manage system-wide knowledge base documents
#
# Only accessible by admin users. Provides UI for:
# - Uploading documents to system RAG
# - Viewing all system documents
# - Re-indexing documents
# - Deleting documents
#
class Admin::SystemDocumentsController < ApplicationController
  before_action :require_admin!
  before_action :set_system_document, only: [:show, :destroy, :reindex, :download]

  def index
    @categories = SystemDocument.categories_with_counts
    @documents = SystemDocument.includes(:uploaded_by, :rag_store)
                               .recent
                               .page(params[:page])
                               .per(20)

    # Filter by category/subcategory if provided
    if params[:category].present?
      @documents = @documents.by_category(params[:category])
    end

    if params[:subcategory].present?
      @documents = @documents.by_subcategory(params[:subcategory])
    end

    # Summary stats
    @total_documents = SystemDocument.count
    @total_storage = SystemDocument.total_storage_used
    @indexed_count = SystemDocument.indexed.count
    @pending_count = SystemDocument.pending_or_processing.count
    @failed_count = SystemDocument.failed.count
  end

  def new
    @document = SystemDocument.new
  end

  def create
    @document = SystemDocument.new(system_document_params)
    @document.uploaded_by = current_user

    # Handle file upload
    uploaded_file = params[:system_document][:file]

    if uploaded_file.blank?
      @document.errors.add(:base, "Please select a file to upload")
      render :new and return
    end

    # Set file metadata
    @document.original_filename = uploaded_file.original_filename
    @document.content_type = uploaded_file.content_type
    @document.file_size_bytes = uploaded_file.size

    if @document.save
      # Upload to S3
      begin
        upload_to_s3(uploaded_file, @document.s3_key)

        # Enqueue indexing job
        SystemDocumentIndexJob.perform_later(@document.id)

        redirect_to admin_system_documents_path,
          notice: "✅ Document uploaded successfully! Indexing will begin shortly."
      rescue => e
        @document.destroy
        Rails.logger.error "S3 upload failed: #{e.message}"
        redirect_to new_admin_system_document_path,
          alert: "Upload failed: #{e.message}"
      end
    else
      render :new
    end
  end

  def show
    # Show document details and indexing status
  end

  def destroy
    begin
      # Delete from S3
      delete_from_s3(@document.s3_key)

      # Delete associated RAG store and all chunks
      @document.rag_store&.destroy

      # Delete the document record
      @document.destroy

      redirect_to admin_system_documents_path,
        notice: "Document deleted successfully"
    rescue => e
      redirect_to admin_system_documents_path,
        alert: "Delete failed: #{e.message}"
    end
  end

  def reindex
    @document.reindex!
    redirect_to admin_system_documents_path,
      notice: "Re-indexing started for #{@document.original_filename}"
  end

  def download
    # Generate pre-signed S3 URL and redirect
    url = generate_download_url(@document.s3_key)
    redirect_to url, allow_other_host: true
  end

  private

  def set_system_document
    @document = SystemDocument.find(params[:id])
  end

  def system_document_params
    params.require(:system_document).permit(
      :category,
      :subcategory,
      :description
    )
  end

  def require_admin!
    unless current_user&.admin?
      redirect_to root_path, alert: "Access denied. Admin privileges required."
    end
  end

  # S3 helper methods

  def upload_to_s3(file, s3_key)
    s3_client.put_object(
      bucket: ENV.fetch('RAG_BUCKET'),
      key: s3_key,
      body: file.read,
      content_type: file.content_type
    )
  end

  def delete_from_s3(s3_key)
    s3_client.delete_object(
      bucket: ENV.fetch('RAG_BUCKET'),
      key: s3_key
    )
  rescue Aws::S3::Errors::NoSuchKey
    # File already deleted, ignore
    Rails.logger.warn "S3 key not found: #{s3_key}"
  end

  def generate_download_url(s3_key)
    s3_client.presigned_url(
      :get_object,
      bucket: ENV.fetch('RAG_BUCKET'),
      key: s3_key,
      expires_in: 300  # 5 minutes
    )
  end

  def s3_client
    @s3_client ||= Aws::S3::Client.new(
      region: ENV.fetch('AWS_REGION', 'us-east-1'),
      endpoint: ENV['AWS_S3_ENDPOINT']  # For LocalStack testing
    )
  end
end
