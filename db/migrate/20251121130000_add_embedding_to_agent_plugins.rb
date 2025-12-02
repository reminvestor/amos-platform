class AddEmbeddingToAgentPlugins < ActiveRecord::Migration[8.0]
  def change
    # Ensure pgvector extension is enabled
    enable_extension "vector"

    # Add embedding column for RAG (1536 dimensions for OpenAI text-embedding-3-small)
    add_column :agent_plugins, :embedding, :vector, limit: 1536
    
    # Add HNSW index for fast similarity search
    add_index :agent_plugins, :embedding, using: :hnsw, opclass: :vector_cosine_ops
  end
end

