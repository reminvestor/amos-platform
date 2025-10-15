# frozen_string_literal: true

# Creates the referrals table to track who was referred by which affiliate.
# Links affiliates to the users/entities they brought to the platform.
class CreateReferrals < ActiveRecord::Migration[8.0]
  def change
    create_table :referrals do |t|
      # Core associations
      t.references :affiliate, null: false, foreign_key: true
      t.references :referred_user, foreign_key: { to_table: :users }
      t.references :referred_entity, foreign_key: { to_table: :entities }

      # Tracking information
      t.string :referral_code_used

      # Status tracking (enum: pending, converted, cancelled)
      t.integer :status, default: 0, null: false

      # Conversion tracking
      t.datetime :converted_at

      # Cookie and tracking data
      t.jsonb :cookie_data, default: {}

      t.timestamps
    end

    # Indexes for performance
    add_index :referrals, [:affiliate_id, :referred_entity_id]
    add_index :referrals, :status
    add_index :referrals, :converted_at
  end
end
