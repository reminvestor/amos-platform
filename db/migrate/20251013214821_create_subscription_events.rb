class CreateSubscriptionEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :subscription_events do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :event_type, null: false
      t.string :previous_status
      t.string :new_status
      t.string :previous_plan
      t.string :new_plan
      t.string :stripe_event_id
      t.jsonb :metadata, default: {}
      t.string :triggered_by

      t.timestamps
    end

    add_index :subscription_events, :event_type
    add_index :subscription_events, :stripe_event_id, unique: true, where: "stripe_event_id IS NOT NULL"
    add_index :subscription_events, [:entity_id, :created_at]
  end
end
