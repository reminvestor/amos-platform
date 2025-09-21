class CreateIntegrations < ActiveRecord::Migration[8.0]
  def change
    create_table :integrations do |t|
      t.string :name
      t.string :slug
      t.string :category
      t.integer :auth_type
      t.jsonb :auth_config
      t.string :api_base_url
      t.jsonb :allowed_hosts
      t.string :documentation_url
      t.string :icon_url
      t.text :description
      t.boolean :is_active
      t.boolean :is_verified
      t.jsonb :metadata

      t.timestamps
    end
    add_index :integrations, :name, unique: true
    add_index :integrations, :slug, unique: true
  end
end
