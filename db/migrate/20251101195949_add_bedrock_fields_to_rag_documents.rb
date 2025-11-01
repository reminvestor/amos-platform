class AddBedrockFieldsToRagDocuments < ActiveRecord::Migration[8.0]
  def change
    add_column :rag_documents, :processing_status, :string
    add_column :rag_documents, :deleted_at, :datetime
    add_column :rag_documents, :metadata, :jsonb, default: {}

    # Add indexes
    add_index :rag_documents, :processing_status
    add_index :rag_documents, :deleted_at
  end
end
