# frozen_string_literal: true

class RemoveTokenVolumeDiscounts < ActiveRecord::Migration[8.0]
  def up
    # Remove volume discounts - margins are slim at 20% markup
    # With 20% uplift: $1.20 buys 100,000 tokens, so $1 buys ~83,333 tokens
    # All tiers now use the same rate with NO bonuses
    
    new_tiers = [
      { 'amount_usd' => 20, 'tokens' => 1_670_000, 'bonus_tokens' => 0 },
      { 'amount_usd' => 50, 'tokens' => 4_170_000, 'bonus_tokens' => 0 },
      { 'amount_usd' => 100, 'tokens' => 8_330_000, 'bonus_tokens' => 0 },
      { 'amount_usd' => 200, 'tokens' => 16_670_000, 'bonus_tokens' => 0 }
    ]

    execute <<-SQL
      UPDATE billing_configurations 
      SET purchase_tiers = '#{new_tiers.to_json}',
          updated_at = NOW()
    SQL
  end

  def down
    # Revert to old tiered pricing with bonuses
    old_tiers = [
      { 'amount_usd' => 20, 'tokens' => 2_000_000, 'bonus_tokens' => 0 },
      { 'amount_usd' => 50, 'tokens' => 5_500_000, 'bonus_tokens' => 500_000 },
      { 'amount_usd' => 100, 'tokens' => 12_000_000, 'bonus_tokens' => 2_000_000 },
      { 'amount_usd' => 200, 'tokens' => 26_000_000, 'bonus_tokens' => 6_000_000 }
    ]

    execute <<-SQL
      UPDATE billing_configurations 
      SET purchase_tiers = '#{old_tiers.to_json}',
          updated_at = NOW()
    SQL
  end
end
