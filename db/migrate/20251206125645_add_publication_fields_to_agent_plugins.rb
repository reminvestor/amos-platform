class AddPublicationFieldsToAgentPlugins < ActiveRecord::Migration[8.0]
  def change
    # Publication workflow fields (check if columns exist first)
    unless column_exists?(:agent_plugins, :is_public)
      add_column :agent_plugins, :is_public, :boolean, default: false, null: false
    end
    
    unless column_exists?(:agent_plugins, :publish_status)
      add_column :agent_plugins, :publish_status, :string, default: 'private', null: false
    end
    
    unless column_exists?(:agent_plugins, :published_at)
      add_column :agent_plugins, :published_at, :datetime
    end
    
    # Security review fields (mirrors ToolDefinition pattern)
    unless column_exists?(:agent_plugins, :security_rating)
      add_column :agent_plugins, :security_rating, :string  # pass, review, fail
    end
    
    unless column_exists?(:agent_plugins, :security_reason)
      add_column :agent_plugins, :security_reason, :text
    end
    
    # Admin review fields
    unless column_exists?(:agent_plugins, :review_notes)
      add_column :agent_plugins, :review_notes, :text
    end
    
    unless column_exists?(:agent_plugins, :reviewed_by_id)
      add_column :agent_plugins, :reviewed_by_id, :bigint
    end
    
    unless column_exists?(:agent_plugins, :reviewed_at)
      add_column :agent_plugins, :reviewed_at, :datetime
    end
    
    # Usage tracking for reputation
    unless column_exists?(:agent_plugins, :usage_count)
      add_column :agent_plugins, :usage_count, :integer, default: 0, null: false
    end
    
    # Indexes for efficient queries (check if they exist)
    unless index_exists?(:agent_plugins, :is_public)
      add_index :agent_plugins, :is_public
    end
    
    unless index_exists?(:agent_plugins, :publish_status)
      add_index :agent_plugins, :publish_status
    end
    
    unless index_exists?(:agent_plugins, :security_rating)
      add_index :agent_plugins, :security_rating
    end
    
    unless index_exists?(:agent_plugins, [:is_public, :publish_status], name: 'idx_agent_plugins_public_status')
      add_index :agent_plugins, [:is_public, :publish_status], name: 'idx_agent_plugins_public_status'
    end
    
    unless index_exists?(:agent_plugins, :reviewed_by_id)
      add_index :agent_plugins, :reviewed_by_id
    end
    
    # Foreign key for reviewer (check if it exists)
    unless foreign_key_exists?(:agent_plugins, :users, column: :reviewed_by_id)
      add_foreign_key :agent_plugins, :users, column: :reviewed_by_id, on_delete: :nullify
    end
  end
end

