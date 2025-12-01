# frozen_string_literal: true

class AddThresholdTrackingToUserBillingAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :user_billing_accounts, :last_threshold_notified, :integer
    add_column :user_billing_accounts, :free_tokens_granted, :integer
    
    # Set free_tokens_granted for existing accounts based on their signup bonus
    reversible do |dir|
      dir.up do
        # For existing accounts, set free_tokens_granted to the current config default
        execute <<-SQL
          UPDATE user_billing_accounts 
          SET free_tokens_granted = (
            SELECT free_tokens_on_signup 
            FROM billing_configurations 
            WHERE is_active = true 
            ORDER BY created_at DESC 
            LIMIT 1
          )
          WHERE free_tokens_granted IS NULL
        SQL
      end
    end
  end
end

