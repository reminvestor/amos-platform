# frozen_string_literal: true

# Creates the payouts table to track payment batches sent to affiliates.
# Each payout represents a collection of approved commissions being paid out.
class CreatePayouts < ActiveRecord::Migration[8.0]
  def change
    create_table :payouts do |t|
      # Core association
      t.references :affiliate, null: false, foreign_key: true

      # Payout amount
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :currency, default: "USD", null: false

      # Payment details
      t.string :payment_method  # paypal, stripe, manual
      t.string :payment_reference

      # Status tracking (enum: pending, processing, completed, failed)
      t.integer :status, default: 0, null: false

      # Payout scheduling
      t.date :payout_date

      # Admin notes
      t.text :notes

      # Commission tracking (array of commission IDs included in this payout)
      t.integer :commission_ids, array: true, default: []

      # Processing tracking
      t.references :processed_by, foreign_key: { to_table: :admin_users }

      t.timestamps
    end

    # Indexes for performance and filtering
    add_index :payouts, [:affiliate_id, :status]
    add_index :payouts, :payout_date
    add_index :payouts, :status
  end
end
