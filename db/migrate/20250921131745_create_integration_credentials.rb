class CreateIntegrationCredentials < ActiveRecord::Migration[8.0]
  def change
    create_table :integration_credentials do |t|
      t.belongs_to :connection, null: false, foreign_key: true
      t.string :name
      t.text :credentials
      t.string :auth_method
      t.string :auth_field_name
      t.string :token_type
      t.datetime :expires_at
      t.datetime :rotates_at
      t.datetime :rotated_at
      t.datetime :last_refresh_at
      t.text :last_refresh_error
      t.integer :status
      t.jsonb :metadata

      t.timestamps
    end
  end
end
