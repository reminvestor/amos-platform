class CreateOAuthConfigurations < ActiveRecord::Migration[8.0]
  def change
    create_table :o_auth_configurations do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :integration, null: false, foreign_key: true
      t.string :client_id, null: false
      t.string :client_secret, null: false
      t.string :redirect_uri, null: false
      t.text :scopes
      t.string :authorize_url, null: false
      t.string :token_url, null: false
      t.text :credentials

      t.timestamps
    end

    add_index :o_auth_configurations, [:entity_id, :integration_id], unique: true, name: 'index_oauth_configs_on_entity_integration'
    add_index :o_auth_configurations, :client_id
  end
end
