# frozen_string_literal: true

class FixBillingConfigurationPurchaseTiers < ActiveRecord::Migration[7.1]
  def up
    # Fix the purchase tiers to have correct token amounts (millions, not thousands)
    # $20 = 2,000,000 tokens (not 200,000)
    # Based on: 100,000 tokens = $1
    
    correct_tiers = [
      { 'amount_usd' => 20, 'tokens' => 2_000_000, 'bonus_tokens' => 0 },
      { 'amount_usd' => 50, 'tokens' => 5_500_000, 'bonus_tokens' => 500_000 },
      { 'amount_usd' => 100, 'tokens' => 12_000_000, 'bonus_tokens' => 2_000_000 },
      { 'amount_usd' => 200, 'tokens' => 26_000_000, 'bonus_tokens' => 6_000_000 }
    ]

    execute <<-SQL
      UPDATE billing_configurations 
      SET purchase_tiers = '#{correct_tiers.to_json}',
          updated_at = NOW()
    SQL
  end

  def down
    # Revert to old (incorrect) values if needed
    old_tiers = [
      { 'amount_usd' => 20, 'tokens' => 200_000, 'bonus_tokens' => 0 },
      { 'amount_usd' => 50, 'tokens' => 550_000, 'bonus_tokens' => 50_000 },
      { 'amount_usd' => 100, 'tokens' => 1_200_000, 'bonus_tokens' => 200_000 },
      { 'amount_usd' => 200, 'tokens' => 2_600_000, 'bonus_tokens' => 600_000 }
    ]

    execute <<-SQL
      UPDATE billing_configurations 
      SET purchase_tiers = '#{old_tiers.to_json}',
          updated_at = NOW()
    SQL
  end
end

