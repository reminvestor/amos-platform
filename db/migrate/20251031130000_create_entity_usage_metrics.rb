# db/migrate/20251031_create_entity_usage_metrics.rb
class CreateEntityUsageMetrics < ActiveRecord::Migration[7.1]
  def change
    # Comprehensive usage tracking table
    create_table :entity_usage_metrics do |t|
      t.references :entity, null: false, foreign_key: true

      # Service identification
      t.string :category, null: false  # ai_chat, email, storage, etc.
      t.string :service, null: false   # bedrock_claude, aws_ses, s3_standard, etc.
      t.string :usage_type             # conversation, send, storage, etc.

      # Usage details
      t.decimal :quantity, precision: 20, scale: 6
      t.decimal :rate, precision: 10, scale: 8       # Cost per unit
      t.decimal :calculated_cost_usd, precision: 10, scale: 6

      # Additional context
      t.jsonb :metadata, default: {}

      # Tracking
      t.datetime :tracked_at, null: false
      t.string :tracked_by  # system, user_id, job_name, etc.

      t.timestamps
    end

    # Indexes for reporting
    add_index :entity_usage_metrics, [:entity_id, :tracked_at]
    add_index :entity_usage_metrics, [:entity_id, :category, :tracked_at]
    add_index :entity_usage_metrics, [:entity_id, :category, :service, :tracked_at],
              name: 'idx_entity_metrics_full'
    add_index :entity_usage_metrics, :tracked_at
    add_index :entity_usage_metrics, :category

    # Add cost threshold settings to entities
    add_column :entities, :cost_thresholds, :jsonb, default: {}
    # Example: { "ai_chat": 100.0, "email": 50.0, "total": 500.0 }

    add_column :entities, :billing_tier, :string, default: 'standard'
    # Tiers: free, starter, standard, premium, enterprise

    add_column :entities, :usage_limits, :jsonb, default: {}
    # Example: { "emails_per_month": 10000, "api_calls_per_day": 1000 }

    add_column :entities, :overage_charges_enabled, :boolean, default: false
    add_column :entities, :prepaid_credits, :decimal, precision: 10, scale: 2, default: 0

    # Create a summary table for fast dashboard queries
    create_table :entity_cost_summaries do |t|
      t.references :entity, null: false, foreign_key: true
      t.date :summary_date, null: false

      # Daily totals by category
      t.decimal :ai_chat_cost, precision: 10, scale: 2, default: 0
      t.decimal :email_cost, precision: 10, scale: 2, default: 0
      t.decimal :sms_cost, precision: 10, scale: 2, default: 0
      t.decimal :storage_cost, precision: 10, scale: 2, default: 0
      t.decimal :compute_cost, precision: 10, scale: 2, default: 0
      t.decimal :bandwidth_cost, precision: 10, scale: 2, default: 0
      t.decimal :integration_cost, precision: 10, scale: 2, default: 0
      t.decimal :other_costs, precision: 10, scale: 2, default: 0
      t.decimal :total_cost, precision: 10, scale: 2, default: 0

      # Usage counts
      t.integer :ai_conversations, default: 0
      t.integer :emails_sent, default: 0
      t.integer :documents_processed, default: 0
      t.integer :api_calls, default: 0
      t.integer :landing_page_views, default: 0
      t.integer :background_jobs, default: 0

      # Performance metrics
      t.float :avg_response_time_ms
      t.float :error_rate
      t.integer :support_tickets, default: 0

      t.timestamps
    end

    add_index :entity_cost_summaries, [:entity_id, :summary_date], unique: true
    add_index :entity_cost_summaries, :summary_date
    add_index :entity_cost_summaries, [:entity_id, :total_cost]
  end
end