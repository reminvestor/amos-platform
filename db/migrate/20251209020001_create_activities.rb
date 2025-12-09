class CreateActivities < ActiveRecord::Migration[8.0]
  def change
    create_table :activities do |t|
      t.references :contact, foreign_key: true
      t.references :opportunity, foreign_key: true
      t.references :user, foreign_key: true                    # Human who performed/created
      t.references :performed_by_agent, foreign_key: { to_table: :agent_plugins }
      t.references :assigned_user, foreign_key: { to_table: :users }
      t.references :assigned_agent, foreign_key: { to_table: :agent_plugins }
      t.references :entity, null: false, foreign_key: true
      
      t.string :activity_type, null: false                     # note, email, call, meeting, task, form_submission, ai_action
      t.string :subject
      t.text :description
      t.datetime :scheduled_at                                 # For planned activities/tasks
      t.datetime :due_at                                       # Deadline for tasks
      t.datetime :completed_at
      t.string :outcome                                        # For calls/meetings: connected, voicemail, no_answer, etc.
      t.string :status, null: false, default: 'pending'        # pending, in_progress, completed, cancelled
      t.string :priority, default: 'normal'                    # low, normal, high, urgent
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end

    add_index :activities, :activity_type
    add_index :activities, :status
    add_index :activities, :priority
    add_index :activities, :scheduled_at
    add_index :activities, :due_at
    add_index :activities, [:entity_id, :activity_type]
    add_index :activities, [:contact_id, :created_at]
    add_index :activities, [:opportunity_id, :created_at]
    add_index :activities, [:assigned_user_id, :status]
    add_index :activities, [:assigned_agent_id, :status]
  end
end
