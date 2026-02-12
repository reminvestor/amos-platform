class AddCompositeIndexForAccountLockout < ActiveRecord::Migration[8.0]
  def change
    # Add composite index for efficient account lockout queries
    # Supports: failed_login_attempts >= 5 && last_failed_login_at > 30.minutes.ago
    add_index :users, [:failed_login_attempts, :last_failed_login_at],
              name: 'index_users_on_lockout_fields'
  end
end
