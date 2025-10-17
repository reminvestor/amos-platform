# frozen_string_literal: true

# Creates the affiliate_tiers table to define different commission levels.
# Allows for tiered commission structures (Bronze, Silver, Gold, etc.).
class CreateAffiliateTiers < ActiveRecord::Migration[8.0]
  def change
    create_table :affiliate_tiers do |t|
      # Tier identification
      t.string :name, null: false

      # Commission rate for this tier
      t.decimal :commission_rate, precision: 5, scale: 4, null: false

      # Requirements to reach this tier
      t.integer :min_referrals, default: 0, null: false

      # Additional benefits for this tier (stored as JSON)
      t.jsonb :benefits, default: {}

      # Status
      t.boolean :is_active, default: true, null: false

      t.timestamps
    end

    # Indexes
    add_index :affiliate_tiers, :name, unique: true
    add_index :affiliate_tiers, :min_referrals
    add_index :affiliate_tiers, :is_active
  end
end
