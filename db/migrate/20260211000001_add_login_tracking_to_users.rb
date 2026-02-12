class AddLoginTrackingToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :failed_login_attempts, :integer, default: 0, null: false
    add_column :users, :last_failed_login_at, :datetime
    add_column :users, :locked_until, :datetime

    add_index :users, :failed_login_attempts
  end
end
