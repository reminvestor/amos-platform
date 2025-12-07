# Unified Memory System Migration
#
# Transforms session-based conversations into a unified continuous stream
# with tiered memory layers for efficient context retrieval.
#
class AddUnifiedMemoryToScoutMessages < ActiveRecord::Migration[7.1]
  def change
    # Add memory layer tracking to scout_messages
    add_column :scout_messages, :memory_layer, :string, default: 'l1'
    add_column :scout_messages, :summarized, :boolean, default: false
    add_column :scout_messages, :summary_id, :bigint
    add_column :scout_messages, :importance_score, :float, default: 0.5
    add_column :scout_messages, :topics, :text  # JSON array of extracted topics
    add_column :scout_messages, :embedding_id, :string  # For RAG lookup
    
    # Add indexes for fast memory layer queries
    add_index :scout_messages, [:user_id, :entity_id, :memory_layer]
    add_index :scout_messages, [:user_id, :entity_id, :created_at]
    add_index :scout_messages, [:user_id, :entity_id, :summarized]
    add_index :scout_messages, :importance_score
    
    # Create memory_segments table for L3/L4 summarized segments
    create_table :memory_segments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      
      # Segment tracking
      t.string :segment_type, null: false  # daily, weekly, topic, milestone
      t.datetime :period_start
      t.datetime :period_end
      t.integer :message_count, default: 0
      
      # Content
      t.text :summary, null: false
      t.text :key_topics  # JSON array
      t.text :key_decisions  # JSON array
      t.text :action_items  # JSON array
      t.text :context_snapshot  # Important context at that time
      
      # For semantic search
      t.string :embedding_id
      t.float :relevance_decay, default: 1.0  # Decreases over time
      
      # Retrieval tracking
      t.integer :retrieval_count, default: 0
      t.datetime :last_retrieved_at
      
      t.boolean :active, default: true
      t.timestamps
    end
    
    add_index :memory_segments, [:user_id, :entity_id, :segment_type]
    add_index :memory_segments, [:user_id, :entity_id, :period_start]
    add_index :memory_segments, [:user_id, :entity_id, :active]
    
    # Create memory_bookmarks for user-saved conversation points
    create_table :memory_bookmarks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.references :scout_message, null: false, foreign_key: true
      t.references :agent_work_item, foreign_key: true
      
      # Bookmark details
      t.string :title, null: false
      t.text :description
      t.text :context_snapshot  # Messages around bookmark for context
      t.string :bookmark_type, default: 'saved'  # saved, milestone, shared
      
      # Sharing
      t.boolean :shareable, default: false
      t.string :share_token
      t.datetime :shared_at
      t.integer :view_count, default: 0
      
      t.timestamps
    end
    
    add_index :memory_bookmarks, [:user_id, :entity_id]
    add_index :memory_bookmarks, :share_token, unique: true
    add_index :memory_bookmarks, :bookmark_type
    
    # Add saved_output work type if not exists
    # (handled in model validation update)
  end
end
