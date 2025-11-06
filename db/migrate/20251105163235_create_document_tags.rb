class CreateDocumentTags < ActiveRecord::Migration[8.0]
  def change
    create_table :document_tags do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :name, null: false, limit: 100
      t.string :category, limit: 50 # 'topic', 'type', 'status', 'priority', 'custom'
      t.string :color, limit: 7 # optional hex color
      t.integer :usage_count, default: 0
      t.timestamps
    end
    
    add_index :document_tags, [:entity_id, :name, :category], unique: true
    add_index :document_tags, :usage_count
    add_index :document_tags, [:entity_id, :category]
    
    # Junction table for documents to tags
    create_table :document_tag_assignments do |t|
      t.references :rag_document, null: false, foreign_key: true
      t.references :document_tag, null: false, foreign_key: true
      t.timestamps
    end
    
    add_index :document_tag_assignments,
              [:rag_document_id, :document_tag_id],
              unique: true,
              name: 'idx_doc_tag_unique'
              
    # Document relationships table
    create_table :document_relationships do |t|
      t.references :source_document, null: false, foreign_key: { to_table: :rag_documents }
      t.references :target_document, null: false, foreign_key: { to_table: :rag_documents }
      t.string :relationship_type, null: false # 'references', 'supersedes', 'related_to', 'version_of'
      t.jsonb :metadata, default: {}
      t.timestamps
    end
    
    add_index :document_relationships,
              [:source_document_id, :target_document_id, :relationship_type],
              unique: true,
              name: 'idx_doc_relationship_unique'
    add_index :document_relationships, :relationship_type
  end
end