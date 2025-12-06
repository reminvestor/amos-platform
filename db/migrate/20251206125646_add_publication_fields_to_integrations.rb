class AddPublicationFieldsToIntegrations < ActiveRecord::Migration[8.0]
  def change
    # Publication workflow fields
    add_column :integrations, :is_public, :boolean, default: false, null: false
    add_column :integrations, :publish_status, :string, default: 'private', null: false
    add_column :integrations, :published_at, :datetime
    
    # Admin review fields
    add_column :integrations, :reviewed_by_id, :bigint
    add_column :integrations, :reviewed_at, :datetime
    add_column :integrations, :review_notes, :text
    
    # Usage tracking
    add_column :integrations, :usage_count, :integer, default: 0, null: false
    
    # Creator tracking (if not already present)
    unless column_exists?(:integrations, :created_by_id)
      add_column :integrations, :created_by_id, :bigint
      add_foreign_key :integrations, :users, column: :created_by_id, on_delete: :nullify
    end
    
    # Indexes
    add_index :integrations, :is_public
    add_index :integrations, :publish_status
    add_index :integrations, [:is_public, :publish_status], name: 'idx_integrations_public_status'
    add_index :integrations, :reviewed_by_id
    
    # Foreign key for reviewer
    add_foreign_key :integrations, :users, column: :reviewed_by_id, on_delete: :nullify
  end
end

