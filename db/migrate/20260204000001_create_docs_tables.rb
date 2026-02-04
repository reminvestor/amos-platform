# frozen_string_literal: true

class CreateDocsTables < ActiveRecord::Migration[7.1]
  def change
    # Documentation categories
    create_table :doc_categories do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :icon
      t.boolean :capability_docs, default: false # If true, exposed via API for AMOS
      t.integer :position, default: 0
      
      t.timestamps
    end
    add_index :doc_categories, :slug, unique: true
    add_index :doc_categories, :capability_docs
    
    # Documentation pages (wiki-style)
    create_table :doc_pages do |t|
      t.string :title, null: false
      t.string :slug, null: false
      t.text :content
      t.text :summary
      t.references :doc_category, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :last_edited_by, foreign_key: { to_table: :users }
      t.boolean :featured, default: false
      t.boolean :published, default: true
      t.integer :view_count, default: 0
      
      # For AMOS capability queries
      t.string :keywords, array: true, default: []
      t.jsonb :examples, default: []
      t.jsonb :parameters, default: {}
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end
    add_index :doc_pages, :slug, unique: true
    add_index :doc_pages, :featured
    add_index :doc_pages, :published
    add_index :doc_pages, :keywords, using: :gin
    
    # Page revision history
    create_table :doc_page_revisions do |t|
      t.references :doc_page, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.text :content
      t.text :previous_content
      t.string :action # created, updated, reverted
      t.string :summary # Edit summary
      t.string :ai_generated_by # If edited by AI, which model
      
      t.timestamps
    end
    add_index :doc_page_revisions, [:doc_page_id, :created_at]
    
    # AI-suggested documentation updates
    create_table :doc_suggestions do |t|
      t.references :doc_page, foreign_key: true # nil for new page suggestions
      t.string :suggested_by # 'amos', user_id, etc.
      t.string :suggestion_type # 'update', 'new_page', 'correction'
      t.string :title
      t.text :content
      t.text :rationale
      t.string :source # 'ai_observation', 'user_feedback', 'auto_generated'
      t.string :status, default: 'pending' # pending, approved, rejected
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.datetime :reviewed_at
      
      t.timestamps
    end
    add_index :doc_suggestions, :status
    add_index :doc_suggestions, :suggested_by
    
    # Related pages (many-to-many)
    create_table :doc_page_relations do |t|
      t.references :doc_page, null: false, foreign_key: true
      t.references :related_page, null: false, foreign_key: { to_table: :doc_pages }
      t.string :relation_type, default: 'related' # related, prerequisite, see_also
      
      t.timestamps
    end
    add_index :doc_page_relations, [:doc_page_id, :related_page_id], unique: true
  end
end
