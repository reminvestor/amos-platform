class AddPublicationFieldsToAgentPlugins < ActiveRecord::Migration[8.0]
  def change
    # Publication workflow fields
    add_column :agent_plugins, :is_public, :boolean, default: false, null: false
    add_column :agent_plugins, :publish_status, :string, default: 'private', null: false
    add_column :agent_plugins, :published_at, :datetime
    
    # Security review fields (mirrors ToolDefinition pattern)
    add_column :agent_plugins, :security_rating, :string  # pass, review, fail
    add_column :agent_plugins, :security_reason, :text
    
    # Admin review fields
    add_column :agent_plugins, :review_notes, :text
    add_column :agent_plugins, :reviewed_by_id, :bigint
    add_column :agent_plugins, :reviewed_at, :datetime
    
    # Usage tracking for reputation
    add_column :agent_plugins, :usage_count, :integer, default: 0, null: false
    
    # Indexes for efficient queries
    add_index :agent_plugins, :is_public
    add_index :agent_plugins, :publish_status
    add_index :agent_plugins, :security_rating
    add_index :agent_plugins, [:is_public, :publish_status], name: 'idx_agent_plugins_public_status'
    add_index :agent_plugins, :reviewed_by_id
    
    # Foreign key for reviewer
    add_foreign_key :agent_plugins, :users, column: :reviewed_by_id, on_delete: :nullify
  end
end

