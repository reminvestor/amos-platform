class AddEnhancedMetadataToRagStores < ActiveRecord::Migration[8.0]
  def change
    # Add rich metadata columns to support enhanced search and filtering
    # These columns mirror the metadata stored in Pinecone vectors
    add_column :rag_stores, :metadata_schema_version, :integer, default: 1

    # Note: Individual chunk metadata is stored in Pinecone vectors
    # These columns are for store-level configuration
    add_column :rag_stores, :supports_page_filtering, :boolean, default: true
    add_column :rag_stores, :supports_section_filtering, :boolean, default: true
    add_column :rag_stores, :supports_heading_search, :boolean, default: true

    # Statistics about metadata richness
    add_column :rag_stores, :avg_chunk_tokens, :integer
    add_column :rag_stores, :chunks_with_pages, :integer, default: 0
    add_column :rag_stores, :chunks_with_headings, :integer, default: 0
    add_column :rag_stores, :chunks_with_tables, :integer, default: 0
  end
end
