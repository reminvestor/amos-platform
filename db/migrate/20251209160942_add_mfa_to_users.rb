# frozen_string_literal: true

class AddMfaToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :otp_secret, :string
    add_column :users, :otp_required_for_login, :boolean, default: false, null: false
    add_column :users, :otp_backup_codes, :text
    add_column :users, :otp_email_enabled, :boolean, default: true, null: false
    add_column :users, :otp_delivery_method, :string, default: "totp"
    add_column :users, :last_otp_at, :datetime
    add_column :users, :otp_failed_attempts, :integer, default: 0, null: false
    add_column :users, :otp_locked_at, :datetime

    add_index :users, :otp_required_for_login
  end
end
