class CreateOAuthConfigurations < ActiveRecord::Migration[8.0]
  def change
    create_table :o_auth_configurations do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :integration, null: false, foreign_key: true
      t.string :client_id
      t.string :client_secret
      t.string :redirect_uri
      t.text :scopes
      t.string :authorize_url
      t.string :token_url
      t.text :credentials

      t.timestamps
    end
  end
end
