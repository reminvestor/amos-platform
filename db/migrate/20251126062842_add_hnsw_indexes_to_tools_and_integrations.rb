class AddHnswIndexesToToolsAndIntegrations < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # Add HNSW index to tool_definitions for fast vector similarity search
    # HNSW (Hierarchical Navigable Small World) provides O(log n) search performance
    add_index :tool_definitions, :embedding,
              using: :hnsw,
              opclass: :vector_cosine_ops,
              algorithm: :concurrently,
              name: "index_tool_definitions_on_embedding_hnsw",
              if_not_exists: true

    # Add HNSW index to integrations for fast vector similarity search
    add_index :integrations, :embedding,
              using: :hnsw,
              opclass: :vector_cosine_ops,
              algorithm: :concurrently,
              name: "index_integrations_on_embedding_hnsw",
              if_not_exists: true

    # Add HNSW index to integration_operations for operation discovery
    # First need to add embedding column if it doesn't exist
    unless column_exists?(:integration_operations, :embedding)
      add_column :integration_operations, :embedding, :vector, limit: 1536
    end

    add_index :integration_operations, :embedding,
              using: :hnsw,
              opclass: :vector_cosine_ops,
              algorithm: :concurrently,
              name: "index_integration_operations_on_embedding_hnsw",
              if_not_exists: true
  end
end
