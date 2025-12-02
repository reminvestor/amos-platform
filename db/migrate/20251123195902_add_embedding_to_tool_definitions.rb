class AddEmbeddingToToolDefinitions < ActiveRecord::Migration[8.0]
  def change
    add_column :tool_definitions, :embedding, :vector, limit: 1536
  end
end
