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
  belongs_to :rag_store
  has_many :rag_chunks, dependent: :destroy

  # Validations
  validates :file_hash, presence: true
  validates :original_filename, presence: true

  # Scopes
  scope :for_entity, ->(entity) {
    joins(:rag_store).where(rag_stores: { entity_id: entity.id })
  }
  scope :with_docling_metadata, -> { where.not(docling_metadata: {}) }
  scope :by_content_type, ->(type) { where(content_type: type) }

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

  # S3 URL helpers
  def s3_url
    "#{rag_store.s3_raw_path}/#{id}/#{original_filename}"
  end

  def docling_output_url
    "#{rag_store.s3_docling_output_path}/#{id}/full_output.json"
  end

  def processed_chunks_url
    "#{rag_store.s3_processed_path}/#{id}/chunks.json"
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
end
