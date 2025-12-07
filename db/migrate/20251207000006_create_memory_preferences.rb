# User Memory Preferences
#
# Allows users to control their memory/privacy settings
#
class CreateMemoryPreferences < ActiveRecord::Migration[7.1]
  def change
    create_table :memory_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      
      # Memory retention
      t.integer :retention_days, default: 90        # How long to keep raw messages
      t.boolean :auto_summarize, default: true      # Auto-create memory segments
      t.integer :summarize_after_messages, default: 50  # Messages before summarization
      
      # Privacy controls
      t.boolean :memory_enabled, default: true      # Master switch for memory
      t.boolean :learn_preferences, default: true   # Learn user preferences
      t.boolean :learn_business_facts, default: true # Learn about their business
      t.boolean :cross_session_memory, default: true # Remember across sessions
      
      # What to forget
      t.text :forget_topics                         # JSON array of topics to not remember
      t.boolean :forget_after_session, default: false # Clear after each session
      
      # Sharing defaults
      t.boolean :allow_sharing, default: true       # Can create shareable bookmarks
      t.boolean :default_shareable, default: false  # New bookmarks shareable by default
      
      # Notifications
      t.boolean :notify_on_summary, default: false  # Notify when summary created
      t.boolean :notify_on_learn, default: false    # Notify when something learned
      
      t.timestamps
    end
    
    add_index :memory_preferences, [:user_id, :entity_id], unique: true
  end
end
