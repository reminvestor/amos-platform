class CreateAgentLightningWebhooks < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_lightning_webhooks do |t|
      t.references :entity, null: false, foreign_key: true

      t.string :event_type, null: false  # training_completed, training_failed, success_rate_improved, etc
      t.string :url, null: false         # Webhook URL
      t.jsonb :headers, null: false, default: {}  # Custom headers
      t.boolean :active, default: true

      t.integer :total_calls, default: 0
      t.integer :successful_calls, default: 0
      t.integer :failed_calls, default: 0

      t.datetime :last_triggered_at
      t.text :last_error

      t.timestamps

      t.index [:entity_id, :event_type], unique: true
      t.index :event_type
      t.index :active
    end

    create_table :agent_lightning_webhook_logs do |t|
      t.references :agent_lightning_webhook, null: false, foreign_key: true

      t.string :event_type, null: false
      t.jsonb :payload, null: false, default: {}

      t.string :status, null: false, default: "pending"  # pending, success, failed
      t.text :error_message

      t.datetime :completed_at
      t.integer :response_code
      t.text :response_body

      t.timestamps

      t.index :event_type
      t.index :status
      t.index :created_at
    end
  end
end
