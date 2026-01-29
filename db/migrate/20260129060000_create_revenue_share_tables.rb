# frozen_string_literal: true

class CreateRevenueShareTables < ActiveRecord::Migration[7.0]
  def change
    # Track each revenue distribution period
    create_table :revenue_distributions do |t|
      t.string :period, null: false  # e.g., "2026-01"
      t.decimal :gross_revenue, precision: 15, scale: 2, null: false
      t.decimal :holder_pool, precision: 15, scale: 2, null: false
      t.decimal :usdc_distributed, precision: 15, scale: 2, default: 0
      t.decimal :buyback_burned, precision: 20, scale: 4, default: 0
      t.integer :recipients_count, default: 0
      t.datetime :distributed_at
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :revenue_distributions, :period, unique: true
    add_index :revenue_distributions, :distributed_at

    # Track individual payments to users
    create_table :revenue_payments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :revenue_distribution, foreign_key: true
      
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.string :currency, null: false, default: 'USDC'
      t.string :period, null: false
      t.string :status, null: false, default: 'pending'  # pending, credited, transferred, failed
      t.string :payment_method  # platform_credit, solana_transfer, bank_transfer
      
      t.string :transaction_signature  # Solana tx if transferred
      t.datetime :paid_at
      
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :revenue_payments, :period
    add_index :revenue_payments, :status
    add_index :revenue_payments, [:user_id, :period], unique: true

    # Track buyback operations
    create_table :token_buybacks do |t|
      t.string :period, null: false
      t.decimal :usdc_amount, precision: 15, scale: 2, null: false
      t.decimal :estimated_tokens, precision: 20, scale: 4
      t.decimal :actual_tokens_bought, precision: 20, scale: 4
      t.decimal :token_price_at_buyback, precision: 15, scale: 6
      t.string :status, null: false, default: 'pending'  # pending, completed, failed
      
      t.string :swap_transaction_signature
      t.string :burn_transaction_signature
      t.datetime :executed_at
      
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :token_buybacks, :period
    add_index :token_buybacks, :status
  end
end
