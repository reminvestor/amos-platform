class ConversationEmbedding < ApplicationRecord
  belongs_to :scout_message, optional: true
  belongs_to :entity
  
  has_neighbors :embedding
  
  validates :content, presence: true
  validates :role, inclusion: { in: %w[user assistant] }
  
  scope :recent, -> { order(created_at: :desc) }
  scope :by_role, ->(role) { where(role: role) }
  
  # Create from scout message
  def self.from_scout_message(message, embedding)
    create!(
      scout_message: message,
      entity: message.entity,
      content: message.content,
      role: message.is_from_user ? 'user' : 'assistant',
      embedding: embedding
    )
  end
  
  # Find relevant conversation context
  def self.find_relevant_context(query_embedding, entity_id:, limit: 10, time_window: 30.days)
    where(entity_id: entity_id)
      .where('created_at > ?', time_window.ago)
      .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
      .limit(limit)
  end
  
  # Build conversation context from embeddings
  def self.build_context(embeddings)
    embeddings.map { |e| "[#{e.role}]: #{e.content}" }.join("\n\n")
  end
end
