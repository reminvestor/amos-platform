class CreateDeviceTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :device_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token, null: false
      t.string :platform, null: false  # 'ios' or 'android'
      t.string :endpoint_arn           # SNS endpoint ARN after registration
      t.boolean :active, default: true, null: false

      t.timestamps
    end
    add_index :device_tokens, :token, unique: true
    add_index :device_tokens, [:user_id, :active]
  end
end
