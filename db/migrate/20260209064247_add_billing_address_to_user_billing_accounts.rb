class AddBillingAddressToUserBillingAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :user_billing_accounts, :billing_address, :jsonb
  end
end
