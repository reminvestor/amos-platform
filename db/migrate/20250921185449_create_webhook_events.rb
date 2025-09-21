class CreateWebhookEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :webhook_events do |t|
      t.references :webhook_subscription, null: false, foreign_key: true
      t.string :event_type
      t.jsonb :payload
      t.integer :response_status
      t.text :response_body
      t.datetime :delivered_at
      t.text :error_message

      t.timestamps
    end
  end
end
