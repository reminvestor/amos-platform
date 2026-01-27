# SystemDocument - Manages system-wide knowledge base documents
#
# These documents are uploaded by admins via UI and automatically indexed into
# System RAG stores, making them queryable by all entities via Scout.
#
# Upload Flow:
#   1. Admin uploads PDF/DOCX/MD via /admin/system_documents
#   2. File stored in S3: system/{category}/{subcategory}/{filename}
#   3. SystemDocumentIndexJob enqueued (background processing)
#   4. Job creates RagStore (type: 'system') + embeddings
#   5. Document becomes queryable via HybridRagQueryService
#
# Categories:
#   - amos_platform: AMOS product docs, architecture, guides
#   - integrations: Third-party API docs (Stripe, HubSpot, etc.)
#   - help_support: Help articles, FAQs, troubleshooting
#   - api_docs: API references and technical documentation
#
class SystemDocument < ApplicationRecord
  # Associations
  belongs_to :uploaded_by, class_name: 'User'
  belongs_to :rag_store, optional: true  # Set when indexed

  # Enums
  enum :category, {
    amos_platform: 'amos_platform',
    integrations: 'integrations',
    help_support: 'help_support',
    api_docs: 'api_docs'
  }, prefix: true

  enum :status, {
    pending: 'pending',        # Uploaded, awaiting indexing
    processing: 'processing',  # Being processed by SystemDocumentIndexJob
    indexed: 'indexed',        # Successfully indexed in RAG
    failed: 'failed'           # Processing failed
  }, prefix: true

  # Validations
  validates :filename, presence: true
  validates :original_filename, presence: true
  validates :file_size_bytes, presence: true, numericality: { greater_than: 0 }
  validates :content_type, presence: true
  validates :category, presence: true
  validates :s3_key, presence: true, uniqueness: true
  validates :status, presence: true

  # File size limit: 50MB
  validates :file_size_bytes, numericality: { less_than_or_equal_to: 50.megabytes }

  # Scopes
  scope :by_category, ->(category) { where(category: category) }
  scope :by_subcategory, ->(subcategory) { where(subcategory: subcategory) }
  scope :indexed, -> { where(status: 'indexed') }
  scope :pending_or_processing, -> { where(status: ['pending', 'processing']) }
  scope :failed, -> { where(status: 'failed') }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  before_validation :set_filename, if: -> { original_filename.present? && filename.blank? }
  before_validation :set_s3_key, if: -> { category.present? && filename.present? && s3_key.blank? }

  # Class methods
  def self.categories_with_counts
    group(:category, :subcategory).count
  end

  def self.total_storage_used
    sum(:file_size_bytes)
  end

  # Instance methods

  # Generate S3 key based on category and subcategory
  # Example: system/integrations/stripe/stripe_api_reference_v2024.pdf
  def generate_s3_key
    parts = ['system', category]
    parts << subcategory if subcategory.present?
    parts << filename
    parts.join('/')
  end

  # Check if document is ready for use
  def ready?
    status_indexed? && rag_store.present?
  end

  # Mark as processing
  def mark_processing!
    update!(status: :processing, error_message: nil)
  end

  # Mark as successfully indexed
  def mark_indexed!(rag_store_record, chunks_count)
    update!(
      status: :indexed,
      rag_store: rag_store_record,
      indexed_at: Time.current,
      chunk_count: chunks_count,
      error_message: nil
    )
  end

  # Mark as failed with error message
  def mark_failed!(error)
    update!(
      status: :failed,
      error_message: error.to_s[0, 1000]  # Truncate long errors (first 1000 chars)
    )
  end

  # Re-trigger indexing
  def reindex!
    update!(status: :pending, error_message: nil)
    SystemDocumentIndexJob.perform_later(id)
  end

  # File type helpers
  def pdf?
    content_type == 'application/pdf'
  end

  def word_doc?
    content_type.in?(['application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/msword'])
  end

  def markdown?
    content_type == 'text/markdown' || original_filename.end_with?('.md')
  end

  def text?
    content_type.start_with?('text/')
  end

  # Human-readable file size
  def human_file_size
    ActiveSupport::NumberHelper.number_to_human_size(file_size_bytes)
  end

  # Display name with category context
  def display_name
    parts = []
    parts << category.titleize
    parts << subcategory.titleize if subcategory.present?
    parts << original_filename
    parts.join(' → ')
  end

  private

  def set_filename
    # Generate unique filename: original_name_timestamp.ext
    timestamp = Time.current.to_i
    ext = File.extname(original_filename)
    base = File.basename(original_filename, ext)
    self.filename = "#{base.parameterize}_#{timestamp}#{ext}"
  end

  def set_s3_key
    self.s3_key = generate_s3_key
  end
end
