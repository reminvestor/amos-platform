# frozen_string_literal: true

# Creates the affiliates table to store core affiliate program records.
# Each user can become an affiliate to earn commissions by referring new customers.
class CreateAffiliates < ActiveRecord::Migration[8.0]
  def change
    create_table :affiliates do |t|
      # Core associations
      t.references :user, null: false, foreign_key: true

      # Affiliate identification
      t.string :affiliate_code, null: false

      # Status tracking (enum: pending, active, suspended, terminated)
      t.integer :status, default: 0, null: false

      # Commission settings
      t.decimal :commission_rate, precision: 5, scale: 4, default: 0.20, null: false  # 20% default

      # Payment information
      t.string :payment_email

      # Application details
      t.text :application_notes

      # Approval tracking
      t.datetime :approved_at
      t.references :approved_by, foreign_key: { to_table: :admin_users }

      # Tier system (bronze/silver/gold)
      t.string :tier, default: "bronze", null: false

      t.timestamps
    end

    # Indexes for performance
    add_index :affiliates, :affiliate_code, unique: true
    add_index :affiliates, :status
    add_index :affiliates, :tier
  end
end
