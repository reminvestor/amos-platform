class CreateDocumentSubjects < ActiveRecord::Migration[8.0]
  def change
    create_table :document_subjects do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.references :parent, foreign_key: { to_table: :document_subjects }
      t.string :color, limit: 7 # hex color for UI
      t.string :icon, limit: 50 # lucide icon name
      t.jsonb :metadata, default: {}
      t.jsonb :rules, default: {} # For smart folders
      t.boolean :is_smart_folder, default: false
      t.integer :position, default: 0 # For ordering
      t.integer :documents_count, default: 0 # Counter cache
      t.timestamps
    end
    
    add_index :document_subjects, [:entity_id, :name, :parent_id], unique: true
    add_index :document_subjects, :is_smart_folder
    add_index :document_subjects, [:entity_id, :position]
    
    # Junction table for documents to subjects
    create_table :document_subject_assignments do |t|
      t.references :rag_document, null: false, foreign_key: true
      t.references :document_subject, null: false, foreign_key: true
      t.references :assigned_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    
    add_index :document_subject_assignments, 
              [:rag_document_id, :document_subject_id], 
              unique: true,
              name: 'idx_doc_subject_unique'
  end
end