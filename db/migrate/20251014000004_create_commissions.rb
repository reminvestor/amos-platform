# frozen_string_literal: true

# Creates the commissions table to track earned commissions for affiliates.
# Each commission is tied to a referral and an entity's payment event.
class CreateCommissions < ActiveRecord::Migration[8.0]
  def change
    create_table :commissions do |t|
      # Core associations
      t.references :affiliate, null: false, foreign_key: true
      t.references :referral, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true

      # Commission details
      t.string :commission_type  # signup_bonus, first_payment, recurring, lifetime
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :currency, default: "USD", null: false

      # Status tracking (enum: pending, approved, paid, cancelled)
      t.integer :status, default: 0, null: false

      # Related subscription event
      t.references :subscription_event, foreign_key: true

      # Approval tracking
      t.datetime :earned_at
      t.datetime :approved_at
      t.references :approved_by, foreign_key: { to_table: :admin_users }

      t.timestamps
    end

    # Indexes for performance and filtering
    add_index :commissions, [:affiliate_id, :status]
    add_index :commissions, [:status, :approved_at]
    add_index :commissions, :commission_type
    add_index :commissions, :earned_at
  end
end
