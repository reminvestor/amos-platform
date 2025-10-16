class CreateTaskSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :task_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :status, default: 'active', null: false
      t.jsonb :state, default: {}, null: false
      t.jsonb :metadata, default: {}, null: false
      t.string :session_type  # 'autonomous', 'interactive', 'hybrid'
      t.string :workflow_id   # For tracking specific workflows

      t.timestamps
    end

    add_index :task_sessions, :status
    add_index :task_sessions, :session_type
    add_index :task_sessions, [ :user_id, :status ]
    add_index :task_sessions, :created_at
  end
end
