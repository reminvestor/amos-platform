# frozen_string_literal: true

class CreateDeviceTokens < ActiveRecord::Migration[7.1]
  def change
    create_table :device_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      
      # Device identification
      t.string :token, null: false              # The device token from APNs/FCM
      t.string :platform, null: false           # 'ios', 'android'
      t.string :platform_arn                    # AWS SNS platform endpoint ARN
      
      # Device metadata
      t.string :device_id                       # Unique device identifier
      t.string :device_name                     # User-friendly device name
      t.string :device_model                    # e.g., "iPhone 15 Pro"
      t.string :os_version                      # e.g., "17.2"
      t.string :app_version                     # e.g., "1.0.0"
      
      # Status
      t.boolean :active, default: true, null: false
      t.datetime :last_used_at
      t.datetime :deactivated_at
      t.string :deactivation_reason             # 'user_logout', 'token_invalid', 'uninstall'
      
      # Notification preferences (device-specific overrides)
      t.jsonb :notification_preferences, default: {}
      
      t.timestamps
    end

    add_index :device_tokens, :token, unique: true
    add_index :device_tokens, :platform_arn, unique: true, where: "platform_arn IS NOT NULL"
    add_index :device_tokens, [:user_id, :platform, :active]
    add_index :device_tokens, :device_id
    add_index :device_tokens, :active
  end
end
