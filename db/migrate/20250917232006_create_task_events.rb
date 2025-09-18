class CreateTaskEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :task_events do |t|
      t.references :task_session, null: false, foreign_key: true
      t.string :event_type, null: false
      t.jsonb :payload, default: {}, null: false
      t.string :step_id  # For tracking which step triggered the event
      t.integer :sequence_number  # For ordering events

      t.timestamps
    end
    
    add_index :task_events, [:task_session_id, :created_at]
    add_index :task_events, :event_type
    add_index :task_events, [:task_session_id, :sequence_number], unique: true
  end
end
