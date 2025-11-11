class AddParallelTaskSupport < ActiveRecord::Migration[8.0]
  def change
    # Add fields to task_sessions for parallel tracking
    add_column :task_sessions, :parent_conversation_id, :string
    add_column :task_sessions, :task_type, :string # voice_immediate, voice_followup, background, etc.
    add_column :task_sessions, :priority, :integer, default: 5
    add_column :task_sessions, :model_preference, :string # haiku, opus, sonnet
    add_column :task_sessions, :assigned_worker_id, :string
    add_column :task_sessions, :progress, :integer, default: 0
    add_column :task_sessions, :started_at, :datetime
    add_column :task_sessions, :estimated_completion_at, :datetime
    
    # Create task dependencies table
    create_table :task_dependencies do |t|
      t.references :task_session, null: false, foreign_key: true
      t.references :depends_on_task, null: false, foreign_key: { to_table: :task_sessions }
      t.string :relationship_type, default: 'blocks' # blocks, informs, optional
      t.timestamps
    end
    
    # Add parallel task result aggregation
    add_column :scout_conversations, :parallel_task_ids, :jsonb, default: []
    add_column :scout_conversations, :aggregated_results, :jsonb
    
    # Indexes for performance
    add_index :task_sessions, :parent_conversation_id
    add_index :task_sessions, :task_type
    add_index :task_sessions, [:status, :priority]
    add_index :task_sessions, [:assigned_worker_id, :status]
    add_index :task_dependencies, [:task_session_id, :depends_on_task_id], unique: true
  end
end
