# frozen_string_literal: true

class EnableAutoReplenishByDefault < ActiveRecord::Migration[8.0]
  def up
    # Change the default for new user billing accounts to have auto_replenish_enabled = true
    change_column_default :user_billing_accounts, :auto_replenish_enabled, from: false, to: true

    # Enable auto-replenish for ALL existing user billing accounts
    # This is safe since we have very few users at this point
    execute <<-SQL
      UPDATE user_billing_accounts
      SET auto_replenish_enabled = TRUE
      WHERE auto_replenish_enabled = FALSE
    SQL

    Rails.logger.info "✅ Enabled auto-replenish for all user billing accounts"
  end

  def down
    change_column_default :user_billing_accounts, :auto_replenish_enabled, from: true, to: false
  end
end

