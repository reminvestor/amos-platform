class CreateSmsCampaigns < ActiveRecord::Migration[8.0]
  def change
    create_table :sms_campaigns do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :name, null: false
      t.text :message_body, null: false
      t.string :from_number
      t.string :status, default: 'draft'
      t.integer :total_recipients, default: 0
      t.integer :delivered_count, default: 0
      t.integer :failed_count, default: 0
      t.datetime :scheduled_at
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    create_table :sms_deliveries do |t|
      t.references :sms_campaign, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.string :to_number, null: false
      t.string :twilio_sid
      t.string :status # queued, sent, delivered, failed
      t.text :error_message
      t.datetime :delivered_at
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :sms_campaigns, [:entity_id, :status]
    add_index :sms_deliveries, [:sms_campaign_id, :status]
    add_index :sms_deliveries, :twilio_sid, unique: true
  end
end
