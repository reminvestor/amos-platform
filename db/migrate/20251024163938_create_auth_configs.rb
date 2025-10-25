class CreateAuthConfigs < ActiveRecord::Migration[8.0]
  def change
    create_table :auth_configs do |t|
      t.references :oauth_configuration, null: false, foreign_key: true
      t.string :auth_key, null: false
      t.string :auth_value
      t.string :auth_placement, null: false, default: 'header'
      t.integer :position, default: 0

      t.timestamps
    end

    add_index :auth_configs, [:oauth_configuration_id, :position]
  end
end
