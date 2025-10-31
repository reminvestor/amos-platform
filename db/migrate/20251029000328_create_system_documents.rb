class CreateSystemDocuments < ActiveRecord::Migration[8.0]
  def change
    create_table :system_documents do |t|
      # File identification
      t.string :filename, null: false
      t.string :original_filename, null: false
      t.integer :file_size_bytes, null: false
      t.string :content_type, null: false

      # Organization
      t.string :category, null: false  # 'amos_platform', 'integrations', 'help_support', 'api_docs'
      t.string :subcategory           # 'stripe', 'hubspot', 'architecture', etc.
      t.text :description             # Optional description

      # S3 Storage
      t.string :s3_key, null: false   # S3 path: system/integrations/stripe/api.pdf

      # Processing status
      t.string :status, default: 'pending', null: false  # pending, processing, indexed, failed
      t.text :error_message           # If status is 'failed'

      # Associations
      t.references :rag_store, foreign_key: true, null: true  # Linked when indexed
      t.references :uploaded_by, foreign_key: { to_table: :users }, null: false

      # Indexing metadata
      t.datetime :indexed_at
      t.integer :chunk_count, default: 0
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    # Indexes for performance
    add_index :system_documents, :category
    add_index :system_documents, [:category, :subcategory]
    add_index :system_documents, :status
    add_index :system_documents, :s3_key, unique: true
  end
end
