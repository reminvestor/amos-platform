# RagChunk - Represents a processed chunk of text with embeddings
#
# Each chunk is a segment of a document that has been:
# - Extracted and chunked using docling or fallback processor
# - Embedded using OpenAI or Bedrock embeddings
# - Stored in PostgreSQL (pgvector) and optionally Pinecone
#
# Key features:
# - pgvector similarity search
# - Full-text search (PostgreSQL GIN index)
# - Entity isolation for multi-tenant security
# - Chunk type classification (text, table, code, formula)

class RagChunk < ApplicationRecord
  belongs_to :rag_document
  has_one :rag_store, through: :rag_document

  # pgvector for similarity search
  # Note: Requires 'neighbor' gem
  has_neighbors :embedding

  # Validations
  validates :content, presence: true
  validates :chunk_index, presence: true

  # Scopes
  scope :for_entity, ->(entity) {
    joins(rag_document: :rag_store)
      .where(rag_stores: { entity_id: entity.id })
  }

  scope :for_rag_store, ->(rag_store) {
    joins(:rag_document)
      .where(rag_documents: { rag_store_id: rag_store.id })
  }

  scope :text_search, ->(query) {
    where("to_tsvector('english', content) @@ plainto_tsquery('english', ?)", query)
  }

  scope :by_type, ->(type) { where(chunk_type: type) }

  scope :embedded, -> { where.not(embedding: nil) }
  scope :pending_embedding, -> { where(embedding: nil) }

  scope :with_page_number, -> { where.not("metadata->>'page' IS NULL") }
  scope :with_section, -> { where.not("metadata->>'section_title' IS NULL") }

  # Find similar chunks using pgvector
  def similar_chunks(limit = 5)
    return [] unless embedding.present?

    self.class
      .nearest_neighbors(:embedding, embedding, distance: "cosine")
      .where.not(id: id)
      .limit(limit)
  end

  # Find similar chunks within same entity
  def similar_chunks_in_entity(limit = 5)
    return [] unless embedding.present? && rag_store.entity

    self.class
      .for_entity(rag_store.entity)
      .nearest_neighbors(:embedding, embedding, distance: "cosine")
      .where.not(id: id)
      .limit(limit)
  end

  # Embedding status
  def embedded?
    embedding.present?
  end

  # Pinecone sync status
  def synced_to_pinecone?
    pinecone_vector_id.present?
  end

  # Metadata helpers
  def page_number
    metadata&.dig("page") || metadata&.dig("page_number")
  end

  def section_title
    metadata&.dig("section_title") || metadata&.dig("section")
  end

  def chunk_type_label
    case chunk_type
    when "text" then "Text"
    when "table" then "Table"
    when "code" then "Code"
    when "formula" then "Formula"
    else "Unknown"
    end
  end

  # Content helpers
  def preview(length = 200)
    return content if content.length <= length
    "#{content[0...length]}..."
  end

  def word_count
    content.split.size
  end

  # Token estimation (rough: 1 token ≈ 4 characters)
  def estimated_tokens
    return token_count if token_count.present?
    (content.length / 4.0).ceil
  end

  # Vector similarity helpers (requires pgvector neighbor gem)
  def cosine_similarity_to(other_chunk)
    return nil unless embedding.present? && other_chunk.embedding.present?

    # Calculate cosine similarity
    # Note: neighbor gem provides this automatically via neighbor_distance
    1 - neighbor_distance if respond_to?(:neighbor_distance)
  end
end
