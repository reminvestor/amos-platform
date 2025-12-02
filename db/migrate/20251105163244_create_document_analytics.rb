class CreateDocumentAnalytics < ActiveRecord::Migration[8.0]
  def change
    create_table :document_analytics do |t|
      t.references :rag_document, null: false, foreign_key: true
      t.date :date, null: false
      t.integer :view_count, default: 0
      t.integer :query_count, default: 0
      t.float :relevance_score_avg
      t.integer :chunk_retrieval_count, default: 0
      t.integer :unique_users, default: 0
      t.integer :download_count, default: 0
      t.jsonb :search_queries, default: [] # Array of queries that retrieved this doc
      t.jsonb :user_breakdown, default: {} # User ID => action count
      t.timestamps
    end
    
    add_index :document_analytics, [:rag_document_id, :date], unique: true
    add_index :document_analytics, :date
    add_index :document_analytics, [:date, :view_count]
    
    # Saved searches table
    create_table :saved_searches do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.jsonb :query_params, null: false # { query: '', filters: {}, use_ai: false }
      t.boolean :alert_enabled, default: false
      t.string :alert_frequency # 'daily', 'weekly', 'monthly'
      t.datetime :last_run_at
      t.datetime :last_alert_at
      t.integer :result_count, default: 0
      t.timestamps
    end
    
    add_index :saved_searches, [:entity_id, :user_id]
    add_index :saved_searches, [:alert_enabled, :last_run_at]
    
    # Document annotations
    create_table :document_annotations do |t|
      t.references :rag_document, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :page_number
      t.jsonb :position # {x, y, width, height} for positioning
      t.text :content, null: false
      t.string :annotation_type # 'note', 'highlight', 'question', 'correction'
      t.string :color # highlight color
      t.boolean :resolved, default: false
      t.references :resolved_by, foreign_key: { to_table: :users }
      t.datetime :resolved_at
      t.timestamps
    end
    
    add_index :document_annotations, [:rag_document_id, :page_number]
    add_index :document_annotations, [:user_id, :created_at]
  end
end