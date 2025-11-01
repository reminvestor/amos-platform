# db/migrate/20251031_create_ocr_metrics_table.rb
class CreateOcrMetricsTable < ActiveRecord::Migration[7.1]
  def change
    # Create table for tracking OCR costs and performance
    create_table :ocr_metrics do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :rag_document, foreign_key: true

      # Provider and processing details
      t.string :provider # 'textract', 'docling', 'comprehend'
      t.string :operation_type # 'analyze_document', 'analyze_expense', 'detect_entities', etc.
      t.string :file_path
      t.integer :file_size_bytes
      t.integer :page_count

      # Performance metrics
      t.integer :processing_time_ms
      t.boolean :fallback_used, default: false
      t.string :fallback_reason

      # Cost tracking
      t.decimal :estimated_cost_usd, precision: 10, scale: 6 # $0.000001 precision
      t.string :pricing_tier # 'standard', 'high_volume', 'free_tier'
      t.jsonb :cost_breakdown # Detailed breakdown of costs

      # AWS specific metrics
      t.string :aws_request_id
      t.integer :api_calls_count, default: 1
      t.integer :characters_processed
      t.integer :tables_extracted
      t.integer :forms_extracted
      t.float :average_confidence

      # Error tracking
      t.string :status # 'success', 'failed', 'partial'
      t.text :error_message

      t.timestamps
    end

    # Indexes for reporting
    add_index :ocr_metrics, :provider
    add_index :ocr_metrics, :created_at
    add_index :ocr_metrics, [:entity_id, :created_at]
    add_index :ocr_metrics, [:entity_id, :provider, :created_at]

    # Add monthly cost tracking to entities
    add_column :entities, :aws_monthly_costs, :jsonb, default: {}
    add_column :entities, :aws_cost_limit_usd, :decimal, precision: 10, scale: 2
    add_column :entities, :aws_cost_alert_threshold, :decimal, precision: 10, scale: 2
    add_column :entities, :last_cost_alert_sent_at, :datetime

    # Create table for aggregated cost reports
    create_table :entity_cost_reports do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :report_period # '2024-11' for monthly
      t.date :period_start
      t.date :period_end

      # Cost breakdown by service
      t.decimal :textract_cost_usd, precision: 10, scale: 2, default: 0
      t.decimal :comprehend_cost_usd, precision: 10, scale: 2, default: 0
      t.decimal :bedrock_cost_usd, precision: 10, scale: 2, default: 0
      t.decimal :s3_cost_usd, precision: 10, scale: 2, default: 0
      t.decimal :total_cost_usd, precision: 10, scale: 2, default: 0

      # Usage metrics
      t.integer :documents_processed, default: 0
      t.integer :pages_processed, default: 0
      t.integer :api_calls_total, default: 0
      t.bigint :bytes_processed, default: 0

      # Service-specific counts
      t.jsonb :service_usage, default: {}
      # Example:
      # {
      #   "textract": { "documents": 100, "pages": 500, "calls": 150 },
      #   "comprehend": { "documents": 80, "calls": 80 },
      #   "bedrock_kb": { "queries": 200, "ingestions": 100 }
      # }

      t.timestamps
    end

    add_index :entity_cost_reports, [:entity_id, :report_period], unique: true
    add_index :entity_cost_reports, :report_period
    add_index :entity_cost_reports, :total_cost_usd
  end
end