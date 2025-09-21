class CreateIntegrationLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :integration_logs do |t|
      t.belongs_to :connection, null: false, foreign_key: true
      t.belongs_to :user, null: false, foreign_key: true
      t.belongs_to :scout_message, null: false, foreign_key: true
      t.belongs_to :integration_operation, null: false, foreign_key: true
      t.string :correlation_id
      t.string :operation_id
      t.string :endpoint
      t.string :http_method
      t.jsonb :request_headers
      t.jsonb :request_body
      t.integer :response_status
      t.jsonb :response_headers
      t.binary :response_body_encrypted
      t.integer :duration_ms
      t.integer :rate_limit_remaining
      t.datetime :rate_limit_reset_at
      t.text :error_message
      t.integer :retry_count
      t.string :idempotency_key
      t.boolean :dry_run
      t.jsonb :metadata

      t.timestamps
    end
    add_index :integration_logs, :correlation_id
  end
end
