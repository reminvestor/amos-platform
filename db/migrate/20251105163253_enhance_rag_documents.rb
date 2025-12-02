class EnhanceRagDocuments < ActiveRecord::Migration[8.0]
  def change
    # Add metadata columns
    add_column :rag_documents, :title, :string, limit: 500
    add_column :rag_documents, :summary, :text
    add_column :rag_documents, :author, :string
    add_column :rag_documents, :document_date, :date
    add_column :rag_documents, :language, :string, limit: 10, default: 'en'
    add_column :rag_documents, :ocr_performed, :boolean, default: false
    
    # Usage tracking
    add_column :rag_documents, :view_count, :integer, default: 0
    add_column :rag_documents, :download_count, :integer, default: 0
    add_column :rag_documents, :last_accessed_at, :timestamp
    add_column :rag_documents, :last_accessed_by_id, :bigint
    
    # Versioning
    add_column :rag_documents, :version, :integer, default: 1
    add_column :rag_documents, :parent_document_id, :bigint
    add_column :rag_documents, :is_latest_version, :boolean, default: true
    
    # Full text search
    add_column :rag_documents, :full_text_search_vector, :tsvector
    
    # Additional metadata
    add_column :rag_documents, :keywords, :jsonb, default: []
    add_column :rag_documents, :custom_metadata, :jsonb, default: {}
    
    # Add foreign keys
    add_foreign_key :rag_documents, :rag_documents, column: :parent_document_id
    add_foreign_key :rag_documents, :users, column: :last_accessed_by_id
    
    # Add indexes
    add_index :rag_documents, :view_count
    add_index :rag_documents, :document_date
    add_index :rag_documents, :author
    add_index :rag_documents, :parent_document_id
    add_index :rag_documents, :is_latest_version
    add_index :rag_documents, :language
    
    # Full text search index
    add_index :rag_documents, :full_text_search_vector, using: :gin
    
    # Create function and trigger for full text search
    reversible do |dir|
      dir.up do
        execute <<-SQL
          CREATE OR REPLACE FUNCTION update_document_search_vector() RETURNS trigger AS $$
          BEGIN
            NEW.full_text_search_vector := 
              setweight(to_tsvector('english', COALESCE(NEW.title, '')), 'A') ||
              setweight(to_tsvector('english', COALESCE(NEW.summary, '')), 'B') ||
              setweight(to_tsvector('english', COALESCE(NEW.original_filename, '')), 'C') ||
              setweight(to_tsvector('english', COALESCE(NEW.author, '')), 'C');
            RETURN NEW;
          END;
          $$ LANGUAGE plpgsql;
          
          CREATE TRIGGER update_document_search_vector_trigger
          BEFORE INSERT OR UPDATE ON rag_documents
          FOR EACH ROW EXECUTE FUNCTION update_document_search_vector();
        SQL
      end
      
      dir.down do
        execute <<-SQL
          DROP TRIGGER IF EXISTS update_document_search_vector_trigger ON rag_documents;
          DROP FUNCTION IF EXISTS update_document_search_vector();
        SQL
      end
    end
  end
end