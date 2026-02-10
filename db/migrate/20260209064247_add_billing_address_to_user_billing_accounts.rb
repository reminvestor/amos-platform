class AddBillingAddressToUserBillingAccounts < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:user_billing_accounts, :billing_address)
      add_column :user_billing_accounts, :billing_address, :jsonb
    end
  end
end
