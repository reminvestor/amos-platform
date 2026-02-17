class CreateUserEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :user_events do |t|
      t.bigint :user_id
      t.bigint :entity_id
      t.string :event_name, null: false
      t.string :event_category, null: false
      t.jsonb :properties, default: {}
      t.string :session_id
      t.string :referrer
      t.string :user_agent
      t.datetime :occurred_at, null: false
      t.timestamps
    end

    add_index :user_events, :user_id
    add_index :user_events, :entity_id
    add_index :user_events, :event_name
    add_index :user_events, :event_category
    add_index :user_events, :occurred_at
    add_index :user_events, :session_id
    add_index :user_events, [:entity_id, :event_name]
    add_index :user_events, [:entity_id, :event_category]
    add_index :user_events, :properties, using: :gin
  end
end
