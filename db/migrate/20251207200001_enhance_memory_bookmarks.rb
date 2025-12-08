# frozen_string_literal: true

class EnhanceMemoryBookmarks < ActiveRecord::Migration[8.0]
  def change
    # Add content_type to distinguish what kind of content is bookmarked
    # Bookmarks are for Scout-user memory (conversations, context, insights)
    # Documents/exports go to AgentWorkItem (the agent inbox)
    add_column :memory_bookmarks, :content_type, :string, default: 'conversation'
    
    # Add content field for storing arbitrary content (context blocks, insights, etc.)
    add_column :memory_bookmarks, :content, :jsonb, default: {}
    
    # Add tags for organization
    add_column :memory_bookmarks, :tags, :jsonb, default: []
    
    # Add source info (what created this bookmark)
    add_column :memory_bookmarks, :source, :string  # 'user', 'scout', 'tool'
    
    # Make scout_message optional (some bookmarks like context blocks may not have a message)
    change_column_null :memory_bookmarks, :scout_message_id, true
    
    # Remove agent_work_item reference (documents go to Work Items, not bookmarks)
    remove_reference :memory_bookmarks, :agent_work_item, foreign_key: true, if_exists: true
    
    # Add index for content_type queries
    add_index :memory_bookmarks, [:user_id, :entity_id, :content_type]
  end
end
