class CreateDeviceTokens < ActiveRecord::Migration[8.0]
  def change
    return if table_exists?(:device_tokens)

    create_table :device_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.string :token, null: false
      t.string :platform, null: false  # 'ios' or 'android'
      t.string :platform_arn           # SNS endpoint ARN after registration
      t.string :device_id
      t.string :device_name
      t.string :device_model
      t.string :os_version
      t.string :app_version
      t.boolean :active, default: true, null: false
      t.datetime :last_used_at
      t.datetime :deactivated_at
      t.string :deactivation_reason
      t.jsonb :notification_preferences, default: {}

      t.timestamps
    end
    add_index :device_tokens, :token, unique: true unless index_exists?(:device_tokens, :token)
    add_index :device_tokens, [:user_id, :active] unless index_exists?(:device_tokens, [:user_id, :active])
    add_index :device_tokens, :active unless index_exists?(:device_tokens, :active)
    add_index :device_tokens, :device_id unless index_exists?(:device_tokens, :device_id)
    add_index :device_tokens, :entity_id unless index_exists?(:device_tokens, :entity_id)
    add_index :device_tokens, :platform_arn, unique: true unless index_exists?(:device_tokens, :platform_arn)
  end
end
