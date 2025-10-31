class CreateRagTables < ActiveRecord::Migration[8.0]
  def change
    # Knowledge base documents with embeddings
    create_table :knowledge_documents do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :title, null: false
      t.text :content, null: false
      t.string :source_type # 'upload', 'website', 'integration'
      t.string :source_url
      t.jsonb :metadata, default: {}
      t.column :embedding, :vector, limit: 1536 # OpenAI/Anthropic embeddings
      t.timestamps
    end
    
    # Document chunks for larger documents
    create_table :document_chunks do |t|
      t.references :knowledge_document, null: false, foreign_key: true
      t.text :content, null: false
      t.integer :chunk_index
      t.column :embedding, :vector, limit: 1536
      t.jsonb :metadata, default: {}
      t.timestamps
    end
    
    # Conversation embeddings for contextual memory
    create_table :conversation_embeddings do |t|
      t.references :scout_message, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.text :content
      t.column :embedding, :vector, limit: 1536
      t.string :role # 'user', 'assistant'
      t.timestamps
    end
    
    # Integration data embeddings (QuickBooks, HubSpot, etc.)
    create_table :integration_embeddings do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :integration, null: false, foreign_key: true
      t.string :resource_type # 'customer', 'invoice', 'contact', etc.
      t.string :resource_id
      t.text :content
      t.column :embedding, :vector, limit: 1536
      t.jsonb :metadata, default: {}
      t.timestamps
    end
    
    # Add indexes for vector similarity search
    add_index :knowledge_documents, :embedding, using: :ivfflat, opclass: :vector_cosine_ops
    add_index :document_chunks, :embedding, using: :ivfflat, opclass: :vector_cosine_ops
    add_index :conversation_embeddings, :embedding, using: :ivfflat, opclass: :vector_cosine_ops
    add_index :integration_embeddings, :embedding, using: :ivfflat, opclass: :vector_cosine_ops
    
    # Compound indexes for filtering
    add_index :knowledge_documents, [:entity_id, :created_at]
    add_index :document_chunks, [:knowledge_document_id, :chunk_index]
    add_index :conversation_embeddings, [:entity_id, :created_at]
    add_index :integration_embeddings, [:entity_id, :integration_id, :resource_type]
  end
end
