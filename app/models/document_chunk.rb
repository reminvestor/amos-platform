class DocumentChunk < ApplicationRecord
  belongs_to :knowledge_document
  
  has_neighbors :embedding
  
  validates :content, presence: true
  validates :chunk_index, presence: true
  
  scope :ordered, -> { order(:chunk_index) }
  
  # Find similar chunks across all documents
  def self.semantic_search(query_embedding, entity_id: nil, limit: 10)
    scope = includes(:knowledge_document)
    scope = scope.joins(:knowledge_document).where(knowledge_documents: { entity_id: entity_id }) if entity_id
    
    scope.nearest_neighbors(:embedding, query_embedding, distance: "cosine")
         .limit(limit)
  end
  
  # Get context with surrounding chunks
  def context(before: 1, after: 1)
    chunks = knowledge_document.document_chunks.ordered
    start_idx = [chunk_index - before, 0].max
    end_idx = chunk_index + after
    
    chunks.where(chunk_index: start_idx..end_idx).pluck(:content).join("\n\n")
  end
end
