class CreateUserMemories < ActiveRecord::Migration[7.1]
  def change
    create_table :user_memories do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      
      # Memory type categorization
      t.string :memory_type, null: false  # preference, fact, decision, goal, pattern
      t.string :category     # communication, workflow, business, personal
      
      # The actual memory content
      t.string :key          # Optional key for lookup (e.g., "preferred_greeting")
      t.text :content, null: false
      
      # Source and confidence
      t.string :source       # conversation, explicit, inferred, observation
      t.float :confidence, default: 0.8  # 0.0 - 1.0
      
      # Tracking
      t.integer :access_count, default: 0
      t.datetime :last_accessed_at
      t.datetime :expires_at  # Optional expiration for time-sensitive memories
      
      t.timestamps
    end
    
    add_index :user_memories, [:user_id, :entity_id, :memory_type]
    add_index :user_memories, [:user_id, :entity_id, :key], unique: true, where: "key IS NOT NULL"
    add_index :user_memories, [:entity_id, :memory_type]
    add_index :user_memories, :confidence
  end
end
