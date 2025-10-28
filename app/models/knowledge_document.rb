class KnowledgeDocument < ApplicationRecord
  belongs_to :entity
  has_many :document_chunks, dependent: :destroy
  
  has_neighbors :embedding
  
  validates :title, presence: true
  validates :content, presence: true
  
  # Source types
  SOURCES = ['upload', 'website', 'integration'].freeze
  
  scope :recent, -> { order(created_at: :desc) }
  scope :by_source, ->(source) { where(source_type: source) }
  
  # Find similar documents
  def similar_documents(limit: 5)
    nearest_neighbors(:embedding, distance: "cosine").limit(limit)
  end
  
  # Chunk large documents
  def create_chunks!(chunk_size: 1000, overlap: 200)
    return if content.length <= chunk_size
    
    chunks = []
    position = 0
    index = 0
    
    while position < content.length
      chunk_content = content[position..(position + chunk_size - 1)]
      
      chunks << document_chunks.build(
        content: chunk_content,
        chunk_index: index,
        metadata: {
          start_position: position,
          end_position: [position + chunk_size - 1, content.length - 1].min
        }
      )
      
      position += (chunk_size - overlap)
      index += 1
    end
    
    chunks
  end
end
