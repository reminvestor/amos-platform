class AddEntityIdToIntegrations < ActiveRecord::Migration[8.0]
  def change
    # entity_id is nullable - NULL means it's a global/system integration
    # Non-null means it's a user-created integration scoped to that entity
    add_reference :integrations, :entity, null: true, foreign_key: true
    add_column :integrations, :is_public, :boolean, default: false, null: false
    add_column :integrations, :created_by_id, :bigint, null: true
    
    add_index :integrations, :is_public
    add_index :integrations, :created_by_id
    add_foreign_key :integrations, :users, column: :created_by_id
  end
end
