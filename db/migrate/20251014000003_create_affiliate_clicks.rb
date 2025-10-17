# frozen_string_literal: true

# Creates the affiliate_clicks table to track every click on affiliate referral links.
# Used for analytics and fraud detection.
class CreateAffiliateClicks < ActiveRecord::Migration[8.0]
  def change
    create_table :affiliate_clicks do |t|
      # Core association
      t.references :affiliate, null: false, foreign_key: true

      # Tracking information
      t.string :referral_code
      t.string :ip_address
      t.text :user_agent
      t.string :referrer
      t.datetime :landed_at
      t.string :session_id

      # Additional metadata (UTM params, etc.)
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    # Indexes for performance and analytics
    add_index :affiliate_clicks, :landed_at
    add_index :affiliate_clicks, [:affiliate_id, :landed_at]
    add_index :affiliate_clicks, :referral_code
    add_index :affiliate_clicks, :ip_address
  end
end
