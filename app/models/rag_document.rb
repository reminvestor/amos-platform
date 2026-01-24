# RagDocument - Represents a single document uploaded to a RAG store
#
# Tracks individual documents with deduplication, metadata extraction,
# and relationships to processed chunks.
#
# Key features:
# - Deduplication via SHA256 file hash
# - Docling metadata storage (tables, images, structure)
# - S3 URL helpers for raw and processed files
# - Association to parent RagStore and child RagChunks

class RagDocument < ApplicationRecord
  include DocumentBroadcasting
  
  belongs_to :rag_store
  has_many :rag_chunks, dependent: :destroy
  
  # Active Storage file attachment
  has_one_attached :file
  
  # New associations for document management
  has_many :document_subject_assignments, dependent: :destroy
  has_many :document_subjects, through: :document_subject_assignments
  has_many :document_tag_assignments, dependent: :destroy
  has_many :document_tags, through: :document_tag_assignments
  has_many :document_analytics, class_name: 'DocumentAnalytics', dependent: :destroy
  has_many :document_annotations, dependent: :destroy
  
  # Self-referential associations for versioning
  belongs_to :parent_document, class_name: 'RagDocument', optional: true
  has_many :child_documents, class_name: 'RagDocument', foreign_key: :parent_document_id
  
  # User tracking
  belongs_to :last_accessed_by, class_name: 'User', optional: true

  # Attribute aliases for backward compatibility
  alias_attribute :file_size, :file_size_bytes

  # Validations
  validates :file_hash, presence: true
  validates :original_filename, presence: true

  # Scopes
  scope :for_entity, ->(entity) {
    joins(:rag_store).where(rag_stores: { entity_id: entity.id })
  }
  scope :with_docling_metadata, -> { where.not(docling_metadata: {}) }
  scope :by_content_type, ->(type) { where(content_type: type) }
  scope :latest_versions, -> { where(is_latest_version: true) }
  scope :recent, -> { order(created_at: :desc) }
  scope :popular, -> { order(view_count: :desc) }
  scope :by_language, ->(lang) { where(language: lang) }

  # Deduplication check
  def duplicate_exists?
    self.class
        .where(file_hash: file_hash)
        .where.not(id: id)
        .exists?
  end

  # Find duplicates
  def self.duplicate_of(file_hash)
    where(file_hash: file_hash)
  end

  # URL helpers for Active Storage
  # Uses direct S3 URLs in production for better reliability
  def file_url(expires_in: 1.year)
    return nil unless file.attached?
    
    if Rails.env.production? && file.blob.service.respond_to?(:url)
      file.blob.url(expires_in: expires_in)
    else
      Rails.application.routes.url_helpers.rails_blob_url(file)
    end
  end
  
  def file_download_url(expires_in: 1.year)
    return nil unless file.attached?
    
    if Rails.env.production? && file.blob.service.respond_to?(:url)
      file.blob.url(expires_in: expires_in, disposition: "attachment; filename=\"#{file.filename}\"")
    else
      Rails.application.routes.url_helpers.rails_blob_url(file, disposition: "attachment")
    end
  end

  # Processing status
  def has_docling_metadata?
    docling_metadata.present? && docling_metadata.any?
  end

  def has_extracted_tables?
    extracted_tables.present? && extracted_tables.any?
  end

  def has_extracted_images?
    extracted_images.present? && extracted_images.any?
  end

  # Summary stats
  def chunks_count
    rag_chunks.count
  end

  def embedded_chunks_count
    rag_chunks.where.not(embedding: nil).count
  end
  
  def chunk_count
    rag_chunks.count
  end
  
  # Get detailed processing stage
  def processing_stage
    return 'completed' if processing_status == 'completed'
    return 'failed' if processing_status == 'failed'
    
    # Check what stage we're at based on data
    if rag_chunks.any?
      embedded_count = embedded_chunks_count
      total_chunks = rag_chunks.count
      
      if embedded_count == total_chunks && total_chunks > 0
        'finalizing' # All embeddings done, waiting for status update
      elsif embedded_count > 0
        'embedding' # Some embeddings done
      else
        'chunking' # Chunks exist but no embeddings yet
      end
    elsif docling_metadata.present? && docling_metadata['extracted_text'].present?
      'chunking' # Text extracted, waiting for chunks
    else
      'extracting' # Still extracting text
    end
  end
  
  # Get human-readable stage description
  def processing_stage_description
    case processing_stage
    when 'extracting'
      'Extracting text and analyzing document structure...'
    when 'chunking'
      'Creating searchable sections from document...'
    when 'embedding'
      "Generating AI embeddings (#{embedded_chunks_count}/#{rag_chunks.count} complete)..."
    when 'finalizing'
      'Finalizing document processing...'
    when 'completed'
      'Ready'
    when 'failed'
      'Processing failed'
    else
      'Processing...'
    end
  end
  
  # Get progress percentage
  def processing_progress
    case processing_stage
    when 'extracting'
      25
    when 'chunking'
      50
    when 'embedding'
      return 75 if rag_chunks.count == 0
      75 + (embedded_chunks_count.to_f / rag_chunks.count * 20)
    when 'finalizing'
      95
    when 'completed'
      100
    when 'failed'
      0
    else
      0
    end
  end

  def embedding_progress
    return 0 if chunks_count.zero?
    ((embedded_chunks_count.to_f / chunks_count) * 100).round(2)
  end

  # File size helpers
  def file_size_mb
    return 0 unless file_size_bytes
    (file_size_bytes.to_f / 1.megabyte).round(2)
  end

  def file_size_human
    return "0 B" unless file_size_bytes

    bytes = file_size_bytes.to_f
    return "#{bytes.round} B" if bytes < 1.kilobyte
    return "#{(bytes / 1.kilobyte).round(2)} KB" if bytes < 1.megabyte
    return "#{(bytes / 1.megabyte).round(2)} MB" if bytes < 1.gigabyte
    "#{(bytes / 1.gigabyte).round(2)} GB"
  end
  
  # Document management methods
  
  # Track document view
  def track_view(user = nil)
    increment!(:view_count)
    update_columns(
      last_accessed_at: Time.current,
      last_accessed_by_id: user&.id
    )
    
    # Track in analytics
    DocumentAnalytics.track_view(self, user) if user
  end
  
  # Track document download
  def track_download(user = nil)
    increment!(:download_count)
    DocumentAnalytics.track_download(self, user) if user
  end
  
  # Add tags
  def add_tags(tag_names, category = 'custom')
    tags = DocumentTag.create_from_list(rag_store.entity, tag_names, category)
    
    tags.each do |tag|
      document_tag_assignments.find_or_create_by(document_tag: tag)
    end
    
    tags
  end
  
  # Remove tags
  def remove_tags(tag_names)
    tags = document_tags.where(name: tag_names.map(&:downcase))
    document_tag_assignments.where(document_tag: tags).destroy_all
  end
  
  # Assign to subjects
  def assign_to_subjects(subject_ids, assigned_by: nil)
    subject_ids = Array(subject_ids)
    
    subjects = rag_store.entity.document_subjects.where(id: subject_ids)
    
    subjects.each do |subject|
      document_subject_assignments.find_or_create_by(
        document_subject: subject,
        assigned_by: assigned_by
      )
    end
  end
  
  # Remove from subjects
  def remove_from_subjects(subject_ids)
    document_subject_assignments.where(document_subject_id: subject_ids).destroy_all
  end
  
  # Full text search
  def self.search(query)
    return all if query.blank?
    
    where(
      "full_text_search_vector @@ plainto_tsquery('english', ?)",
      query
    )
  end
  
  # Filter by multiple criteria
  def self.filter(params = {})
    scope = all
    
    # Subject filter
    if params[:subject_id].present?
      scope = scope.joins(:document_subjects).where(document_subjects: { id: params[:subject_id] })
    end
    
    # Tag filter
    if params[:tags].present?
      tag_names = Array(params[:tags])
      scope = scope.joins(:document_tags).where(document_tags: { name: tag_names }).distinct
    end
    
    # Date range filter
    if params[:date_from].present? || params[:date_to].present?
      date_from = params[:date_from] || 100.years.ago
      date_to = params[:date_to] || Time.current
      scope = scope.where(created_at: date_from..date_to)
    end
    
    # Content type filter
    if params[:content_type].present?
      types = Array(params[:content_type])
      conditions = types.map { |t| "content_type LIKE ?" }
      values = types.map { |t| "%#{t}%" }
      scope = scope.where(conditions.join(' OR '), *values)
    end
    
    # Author filter
    if params[:author].present?
      scope = scope.where("author ILIKE ?", "%#{params[:author]}%")
    end
    
    # Language filter
    if params[:language].present?
      scope = scope.where(language: params[:language])
    end
    
    scope
  end
  
  # Find similar documents using vector similarity
  def find_similar_documents(limit: 5)
    return [] unless embedded_chunks_count > 0
    
    # Get a representative chunk embedding
    representative_chunk = rag_chunks.where.not(embedding: nil).first
    return [] unless representative_chunk
    
    # Find similar chunks using pgvector
    similar_chunks = RagChunk
      .for_entity(rag_store.entity)
      .where.not(embedding: nil)
      .where.not(rag_document_id: id) # Exclude chunks from this document
      .nearest_neighbors(:embedding, representative_chunk.embedding, distance: 'cosine')
      .includes(:rag_document)
      .limit(limit * 3) # Get more to ensure variety after grouping
    
    # Get unique documents
    similar_doc_ids = similar_chunks
      .map(&:rag_document_id)
      .uniq
      .first(limit)
    
    RagDocument.where(id: similar_doc_ids).includes(:document_subjects, :document_tags)
  end
  
  # Create a new version
  def create_version(file, metadata = {})
    new_version = rag_store.rag_documents.create!(
      original_filename: file.original_filename,
      content_type: file.content_type,
      file_size_bytes: file.size,
      file_hash: calculate_file_hash(file),
      parent_document_id: id,
      version: version + 1,
      is_latest_version: true,
      **metadata
    )
    
    # Mark this version as not latest
    update_column(:is_latest_version, false)
    
    # Copy tags and subjects to new version
    document_tags.each do |tag|
      new_version.document_tag_assignments.create!(document_tag: tag)
    end
    
    document_subjects.each do |subject|
      new_version.document_subject_assignments.create!(document_subject: subject)
    end
    
    new_version
  end
  
  # Get all versions
  def all_versions
    if parent_document_id
      parent_document.all_versions
    else
      RagDocument.where("id = ? OR parent_document_id = ?", id, id).order(version: :desc)
    end
  end
  
  # Calculate display title
  def display_title
    title.presence || original_filename
  end
  
  # Get icon based on content type
  def content_type_icon
    case content_type
    when /pdf/i
      'file-text'
    when /word|doc/i
      'file-text'
    when /excel|sheet/i
      'table'
    when /powerpoint|presentation/i
      'presentation'
    when /image/i
      'image'
    when /video/i
      'video'
    when /audio/i
      'music'
    when /json/i
      'code'
    when /html/i
      'globe'
    when /markdown/i
      'file-text'
    else
      'file'
    end
  end
  
  private
  
  def calculate_file_hash(file)
    Digest::SHA256.file(file.path).hexdigest
  end
end
