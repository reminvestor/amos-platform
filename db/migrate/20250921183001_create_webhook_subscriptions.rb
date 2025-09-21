class CreateWebhookSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :webhook_subscriptions do |t|
      t.references :connection, null: false, foreign_key: true
      t.string :endpoint_url
      t.string :signing_secret
      t.jsonb :events
      t.jsonb :filters
      t.integer :status
      t.integer :retry_count
      t.datetime :last_triggered_at
      t.jsonb :metadata

      t.timestamps
    end
  end
end
