class AddPublicationFieldsToIntegrations < ActiveRecord::Migration[8.0]
  def change
    # Publication workflow fields (check if columns exist first)
    unless column_exists?(:integrations, :is_public)
      add_column :integrations, :is_public, :boolean, default: false, null: false
    end
    
    unless column_exists?(:integrations, :publish_status)
      add_column :integrations, :publish_status, :string, default: 'private', null: false
    end
    
    unless column_exists?(:integrations, :published_at)
      add_column :integrations, :published_at, :datetime
    end
    
    # Admin review fields
    unless column_exists?(:integrations, :reviewed_by_id)
      add_column :integrations, :reviewed_by_id, :bigint
    end
    
    unless column_exists?(:integrations, :reviewed_at)
      add_column :integrations, :reviewed_at, :datetime
    end
    
    unless column_exists?(:integrations, :review_notes)
      add_column :integrations, :review_notes, :text
    end
    
    # Usage tracking
    unless column_exists?(:integrations, :usage_count)
      add_column :integrations, :usage_count, :integer, default: 0, null: false
    end
    
    # Creator tracking (if not already present)
    unless column_exists?(:integrations, :created_by_id)
      add_column :integrations, :created_by_id, :bigint
      unless foreign_key_exists?(:integrations, :users, column: :created_by_id)
        add_foreign_key :integrations, :users, column: :created_by_id, on_delete: :nullify
      end
    end
    
    # Indexes (check if they exist)
    unless index_exists?(:integrations, :is_public)
      add_index :integrations, :is_public
    end
    
    unless index_exists?(:integrations, :publish_status)
      add_index :integrations, :publish_status
    end
    
    unless index_exists?(:integrations, [:is_public, :publish_status], name: 'idx_integrations_public_status')
      add_index :integrations, [:is_public, :publish_status], name: 'idx_integrations_public_status'
    end
    
    unless index_exists?(:integrations, :reviewed_by_id)
      add_index :integrations, :reviewed_by_id
    end
    
    # Foreign key for reviewer (check if it exists)
    if column_exists?(:integrations, :reviewed_by_id) && !foreign_key_exists?(:integrations, :users, column: :reviewed_by_id)
      add_foreign_key :integrations, :users, column: :reviewed_by_id, on_delete: :nullify
    end
  end
end

