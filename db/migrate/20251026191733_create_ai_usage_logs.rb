class CreateAiUsageLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_usage_logs do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :scout_message, foreign_key: true
      t.string :model, null: false
      t.integer :input_tokens, default: 0
      t.integer :output_tokens, default: 0
      t.integer :total_tokens, default: 0
      t.decimal :cost_cents, precision: 10, scale: 4, default: 0
      t.integer :duration_ms
      t.string :request_type, default: 'chat'
      t.jsonb :metadata, default: {}

      t.timestamps
    end
    
    # Indexes for efficient querying
    add_index :ai_usage_logs, [:entity_id, :created_at]
    add_index :ai_usage_logs, [:user_id, :created_at]
    add_index :ai_usage_logs, :model
    add_index :ai_usage_logs, :request_type
    add_index :ai_usage_logs, :created_at
  end
end
