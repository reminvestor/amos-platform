# frozen_string_literal: true

class CreateWorkTokenSystem < ActiveRecord::Migration[8.0]
  def change
    # System-wide billing configuration (admin-controlled)
    create_table :billing_configurations do |t|
      t.string :name, null: false, default: 'default'
      t.decimal :uplift_percentage, precision: 5, scale: 2, default: 20.0  # 20% markup
      
      # Token conversion rates (work tokens per unit)
      # These represent the "cost" in work tokens for each resource type
      t.decimal :ai_tokens_rate, precision: 10, scale: 6, default: 1.0      # 1 work token per AI token (adjusted by model)
      t.decimal :email_rate, precision: 10, scale: 4, default: 10.0         # 10 work tokens per email
      t.decimal :storage_rate_mb, precision: 10, scale: 4, default: 1.0     # 1 work token per MB/month
      t.decimal :api_call_rate, precision: 10, scale: 4, default: 0.1       # 0.1 work tokens per API call
      t.decimal :other_compute_rate, precision: 10, scale: 4, default: 100.0 # 100 work tokens per $0.01 of other AWS costs
      
      # Model-specific multipliers (relative to base rate)
      t.jsonb :model_multipliers, default: {
        'claude-sonnet-4-5' => 1.0,
        'claude-3-5-sonnet' => 1.0,
        'claude-3-opus' => 3.0,
        'claude-3-haiku' => 0.1,
        'gpt-4o' => 0.8
      }
      
      # Pricing tiers for work token purchases
      t.jsonb :purchase_tiers, default: [
        { amount_usd: 20, tokens: 200_000, bonus_tokens: 0 },
        { amount_usd: 50, tokens: 550_000, bonus_tokens: 50_000 },
        { amount_usd: 100, tokens: 1_200_000, bonus_tokens: 200_000 },
        { amount_usd: 200, tokens: 2_600_000, bonus_tokens: 600_000 }
      ]
      
      # Free tier settings
      t.integer :free_tokens_on_signup, default: 200_000
      t.integer :default_auto_replenish_amount_usd, default: 20
      t.integer :default_monthly_limit_usd, default: 100
      
      t.boolean :is_active, default: true
      t.timestamps
      
      t.index :name, unique: true
      t.index :is_active
    end

    # User billing account (per user, not entity - users pay for their usage)
    create_table :user_billing_accounts do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      
      # Stripe integration
      t.string :stripe_customer_id
      t.string :stripe_default_payment_method_id
      t.boolean :has_payment_method, default: false
      
      # Work token balance
      t.bigint :work_token_balance, default: 0           # Current balance
      t.bigint :lifetime_tokens_purchased, default: 0    # Total ever purchased
      t.bigint :lifetime_tokens_used, default: 0         # Total ever used
      t.bigint :free_tokens_remaining, default: 200_000  # From signup bonus
      
      # Billing preferences
      t.integer :auto_replenish_amount_usd, default: 20    # Auto-buy this amount
      t.integer :auto_replenish_threshold, default: 10_000 # When balance drops below this
      t.boolean :auto_replenish_enabled, default: true
      t.integer :monthly_limit_usd, default: 100           # Max spend per month
      t.decimal :current_month_spend_usd, precision: 10, scale: 2, default: 0
      
      # Status
      t.string :status, default: 'active'  # active, suspended, closed
      t.datetime :suspended_at
      t.string :suspension_reason
      
      # Timestamps
      t.datetime :last_purchase_at
      t.datetime :last_usage_at
      t.timestamps
      
      t.index :stripe_customer_id, unique: true
      t.index :status
      t.index :work_token_balance
    end

    # Work token transactions (ledger for all token movements)
    create_table :work_token_transactions do |t|
      t.references :user_billing_account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :entity, foreign_key: true  # Optional - which entity the usage was for
      
      # Transaction type
      t.string :transaction_type, null: false  # purchase, usage, refund, bonus, adjustment, expiry
      t.string :category                        # ai_tokens, email, storage, api_call, signup_bonus, etc.
      
      # Token amounts (positive for credits, negative for debits)
      t.bigint :token_amount, null: false
      t.bigint :balance_before, null: false
      t.bigint :balance_after, null: false
      
      # Cost tracking (in USD cents for precision)
      t.integer :raw_cost_cents, default: 0      # Actual AWS/provider cost
      t.integer :uplifted_cost_cents, default: 0 # Cost after markup
      t.decimal :uplift_percentage_applied, precision: 5, scale: 2
      
      # Reference to source (polymorphic)
      t.string :source_type    # AiUsageLog, EmailDelivery, etc.
      t.bigint :source_id
      
      # Stripe reference (for purchases)
      t.string :stripe_payment_intent_id
      t.string :stripe_charge_id
      
      # Description and metadata
      t.string :description
      t.jsonb :metadata, default: {}
      
      t.timestamps
      
      t.index [:user_billing_account_id, :created_at]
      t.index [:transaction_type, :created_at]
      t.index [:category, :created_at]
      t.index [:source_type, :source_id]
      t.index :stripe_payment_intent_id
    end

    # Work token purchases (detailed record of each purchase)
    create_table :work_token_purchases do |t|
      t.references :user_billing_account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :work_token_transaction, foreign_key: true
      
      # Purchase details
      t.integer :amount_usd_cents, null: false
      t.bigint :tokens_purchased, null: false
      t.bigint :bonus_tokens, default: 0
      t.string :purchase_tier  # From billing_configuration tiers
      
      # Stripe details
      t.string :stripe_payment_intent_id
      t.string :stripe_charge_id
      t.string :stripe_invoice_id
      
      # Status
      t.string :status, default: 'pending'  # pending, completed, failed, refunded
      t.string :failure_reason
      
      # Trigger
      t.string :trigger, default: 'manual'  # manual, auto_replenish, admin
      
      t.timestamps
      
      t.index :stripe_payment_intent_id, unique: true
      t.index [:user_billing_account_id, :status]
      t.index :status
    end

    # Usage aggregation (daily rollups for reporting)
    create_table :work_token_usage_summaries do |t|
      t.references :user_billing_account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :entity, foreign_key: true
      
      t.date :summary_date, null: false
      t.string :category, null: false  # ai_tokens, email, storage, api_call
      
      # Aggregated values
      t.bigint :tokens_used, default: 0
      t.integer :transaction_count, default: 0
      t.integer :raw_cost_cents, default: 0
      t.integer :uplifted_cost_cents, default: 0
      
      # Detailed breakdown (for AI tokens)
      t.jsonb :breakdown, default: {}  # e.g., { "claude-sonnet-4-5": 50000, "claude-3-haiku": 10000 }
      
      t.timestamps
      
      t.index [:user_billing_account_id, :summary_date, :category], unique: true, name: 'idx_usage_summary_unique'
      t.index [:summary_date, :category]
    end

    # Add stripe_customer_id to users (moving from entity-level to user-level billing)
    unless column_exists?(:users, :stripe_customer_id)
      add_column :users, :stripe_customer_id, :string
      add_index :users, :stripe_customer_id, unique: true
    end
  end
end

