# frozen_string_literal: true

# SECURITY: Adds clawback tracking for distribution stakes
# 
# Distribution stakes (affiliate sales, referrals) are subject to a 90-day
# clawback period. If the referred customer churns within 90 days, the
# affiliate's token stake is clawed back (returned to treasury).
#
# This prevents self-referral gaming where someone creates a fake customer,
# earns the affiliate reward, then immediately cancels.
class AddClawbackStatusToTokenStakes < ActiveRecord::Migration[7.2]
  def change
    add_column :token_stakes, :clawback_status, :string, default: nil
    
    add_index :token_stakes, :clawback_status
    add_index :token_stakes, [:stake_type, :clawback_status], 
              name: 'index_token_stakes_on_distribution_clawback'
  end
end
