class CreateOauthConfigurations < ActiveRecord::Migration[8.0]
  def change
    create_table :oauth_configurations do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :integration, null: false, foreign_key: true
      t.string :client_id, null: false
      t.string :client_secret, null: false
      t.string :redirect_uri, null: false
      t.text :scopes
      t.jsonb :credentials, default: {}
      t.jsonb :metadata, default: {}
      t.integer :status, default: 0, null: false

      t.timestamps
    end

    add_index :oauth_configurations, [:entity_id, :integration_id], unique: true, name: 'index_oauth_configs_on_entity_and_integration'
  end
end
