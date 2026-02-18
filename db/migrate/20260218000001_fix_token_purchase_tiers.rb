class FixTokenPurchaseTiers < ActiveRecord::Migration[8.0]
  def up
    correct_tiers = [
      { 'amount_usd' => 20, 'tokens' => 2_000_000, 'bonus_tokens' => 0 },
      { 'amount_usd' => 50, 'tokens' => 5_000_000, 'bonus_tokens' => 0 },
      { 'amount_usd' => 100, 'tokens' => 10_000_000, 'bonus_tokens' => 0 },
      { 'amount_usd' => 200, 'tokens' => 20_000_000, 'bonus_tokens' => 0 }
    ]

    BillingConfiguration.find_each do |config|
      config.update_column(:purchase_tiers, correct_tiers)
    end
  end

  def down
    old_tiers = [
      { 'amount_usd' => 20, 'tokens' => 1_670_000, 'bonus_tokens' => 0 },
      { 'amount_usd' => 50, 'tokens' => 4_170_000, 'bonus_tokens' => 0 },
      { 'amount_usd' => 100, 'tokens' => 8_330_000, 'bonus_tokens' => 0 },
      { 'amount_usd' => 200, 'tokens' => 16_670_000, 'bonus_tokens' => 0 }
    ]

    BillingConfiguration.find_each do |config|
      config.update_column(:purchase_tiers, old_tiers)
    end
  end
end
