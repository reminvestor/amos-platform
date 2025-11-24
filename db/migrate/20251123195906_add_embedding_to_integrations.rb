class AddEmbeddingToIntegrations < ActiveRecord::Migration[8.0]
  def change
    add_column :integrations, :embedding, :vector, limit: 1536
  end
end
