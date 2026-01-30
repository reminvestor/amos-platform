class CreateTrustedDevices < ActiveRecord::Migration[8.0]
  def change
    create_table :trusted_devices do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token, null: false
      t.string :device_name
      t.string :device_identifier  # Unique device identifier (e.g., vendor ID)
      t.string :platform           # 'ios' or 'android'
      t.datetime :last_used_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :trusted_devices, :token, unique: true
    add_index :trusted_devices, [:user_id, :device_identifier]
  end
end
