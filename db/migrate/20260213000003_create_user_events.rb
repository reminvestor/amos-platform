class CreateUserEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :user_events do |t|
      t.references :entity, null: true, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.string :event_name, null: false
      t.string :event_category, null: false  # onboarding, navigation, feature, conversion
      t.jsonb :properties, default: {}
      t.string :session_id
      t.string :referrer
      t.string :user_agent
      t.timestamps
    end

    add_index :user_events, [:entity_id, :event_name, :created_at]
    add_index :user_events, [:user_id, :event_name, :created_at]
    add_index :user_events, [:event_name, :created_at]
    add_index :user_events, :event_category
  end
end
