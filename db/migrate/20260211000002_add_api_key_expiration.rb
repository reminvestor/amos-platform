class AddApiKeyExpiration < ActiveRecord::Migration[8.0]
  def change
    # API key expiration tracking
    add_column :users, :api_key_expires_at, :datetime
    add_column :users, :api_key_last_used_at, :datetime

    # Refresh tokens (encrypted)
    add_column :users, :refresh_token_encrypted, :text
    add_column :users, :refresh_token_expires_at, :datetime

    # Indexes for cleanup job
    add_index :users, :api_key_expires_at
    add_index :users, :refresh_token_expires_at

    # Migrate existing users to have 90-day expiration
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE users
          SET api_key_expires_at = NOW() + INTERVAL '90 days',
              api_key_last_used_at = NOW()
          WHERE api_key IS NOT NULL
        SQL
      end
    end
  end
end
