class EnhanceRagStorage < ActiveRecord::Migration[8.0]
  def change
    # Enable pgvector extension for embeddings
    enable_extension 'vector' unless extension_enabled?('vector')

    # Add S3 storage paths and processing metadata to rag_stores
    add_column :rag_stores, :s3_raw_path, :string
    add_column :rag_stores, :s3_processed_path, :string
    add_column :rag_stores, :s3_docling_output_path, :string
    add_column :rag_stores, :token_count, :integer, default: 0
    add_column :rag_stores, :processing_time_ms, :integer
    add_column :rag_stores, :processing_method, :string # 'docling' or 'fallback'
    add_column :rag_stores, :docling_version, :string
    add_column :rag_stores, :last_accessed_at, :datetime
    add_column :rag_stores, :access_count, :integer, default: 0
    add_column :rag_stores, :expires_at, :datetime

    # Add indexes for performance
    add_index :rag_stores, [:entity_id, :status]
    add_index :rag_stores, :last_accessed_at

    # RagDocument - document-level tracking
    create_table :rag_documents do |t|
      t.references :rag_store, foreign_key: true, null: false
      t.string :original_filename, null: false
      t.string :content_type
      t.integer :file_size_bytes
      t.string :file_hash # SHA256 for deduplication
      t.jsonb :docling_metadata, default: {}
      t.jsonb :extracted_tables, default: []
      t.jsonb :extracted_images, default: []
      t.jsonb :document_structure, default: {}
      t.integer :page_count
      t.timestamps
    end
    add_index :rag_documents, :file_hash
    add_index :rag_documents, [:rag_store_id, :file_hash]

    # RagChunk - chunk storage with embeddings and full-text search
    create_table :rag_chunks do |t|
      t.references :rag_document, foreign_key: true, null: false
      t.text :content, null: false
      t.vector :embedding, limit: 1536 # pgvector for OpenAI embeddings
      t.string :pinecone_vector_id
      t.jsonb :metadata, default: {} # page_num, section, chunk_type, etc
      t.integer :chunk_index
      t.integer :token_count
      t.string :chunk_type # 'text', 'table', 'code', 'formula'
      t.timestamps
    end

    # pgvector index for similarity search
    add_index :rag_chunks, :embedding, using: :ivfflat, opclass: :vector_cosine_ops

    # Full-text search index
    execute <<-SQL
      CREATE INDEX index_rag_chunks_on_content_tsvector
      ON rag_chunks
      USING gin(to_tsvector('english', content))
    SQL

    add_index :rag_chunks, :pinecone_vector_id
    add_index :rag_chunks, [:rag_document_id, :chunk_index]

    # RagQuery - usage tracking and caching
    create_table :rag_queries do |t|
      t.references :entity, foreign_key: true, null: false
      t.references :rag_store, foreign_key: true
      t.text :query, null: false
      t.string :query_hash
      t.integer :response_time_ms
      t.jsonb :chunks_retrieved, default: []
      t.jsonb :relevance_scores, default: []
      t.boolean :cache_hit, default: false
      t.timestamps
    end
    add_index :rag_queries, [:entity_id, :query_hash]
    add_index :rag_queries, :created_at
    add_index :rag_queries, :cache_hit

    # RagProcessingJob - job tracking
    create_table :rag_processing_jobs do |t|
      t.references :rag_store, foreign_key: true, null: false
      t.string :job_id # Sidekiq JID
      t.string :job_type
      t.integer :status, default: 0 # 0=pending, 1=processing, 2=completed, 3=failed
      t.text :error_message
      t.integer :retry_count, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :rag_processing_jobs, :job_id
    add_index :rag_processing_jobs, [:rag_store_id, :status]
    add_index :rag_processing_jobs, [:job_type, :status]
  end
end
