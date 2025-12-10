# frozen_string_literal: true

class CreateEntityBillingAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :entity_billing_accounts do |t|
      t.references :entity, null: false, foreign_key: true, index: { unique: true }
      
      # Token balance (can be negative to track overages)
      t.integer :work_token_balance, default: 0, null: false
      
      # Stripe integration
      t.string :stripe_customer_id
      t.string :stripe_default_payment_method_id
      t.boolean :has_payment_method, default: false
      
      # Auto-replenishment settings
      t.boolean :auto_replenish_enabled, default: false
      t.integer :auto_replenish_threshold, default: 10_000
      t.integer :auto_replenish_amount_usd, default: 50
      
      # Limits
      t.integer :monthly_limit_usd, default: 500
      t.integer :current_month_spend_cents, default: 0
      
      # Status
      t.string :status, default: 'active', null: false
      
      # Usage tracking
      t.integer :lifetime_tokens_used, default: 0
      t.integer :lifetime_tokens_purchased, default: 0
      t.datetime :last_usage_at
      t.datetime :last_purchase_at
      
      # Threshold tracking
      t.integer :last_threshold_notified
      t.integer :initial_tokens_granted
      
      t.timestamps
    end
    
    # Add entity_billing_account_id to entity_users for tracking which users are on shared pool
    add_column :entities, :use_shared_token_pool, :boolean, default: false
    add_column :entities, :token_pool_owner_id, :bigint
    add_index :entities, :token_pool_owner_id
    
    # Add tracking to work_token_transactions for entity-level transactions
    add_reference :work_token_transactions, :entity_billing_account, foreign_key: true, index: true
    
    # Add tracking to work_token_usage_summaries for entity-level summaries
    add_reference :work_token_usage_summaries, :entity_billing_account, foreign_key: true, index: true
  end
end
