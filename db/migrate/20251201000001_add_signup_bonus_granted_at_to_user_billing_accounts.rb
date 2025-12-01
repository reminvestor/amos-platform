class AddSignupBonusGrantedAtToUserBillingAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :user_billing_accounts, :signup_bonus_granted_at, :datetime
    add_index :user_billing_accounts, :signup_bonus_granted_at
  end
end

