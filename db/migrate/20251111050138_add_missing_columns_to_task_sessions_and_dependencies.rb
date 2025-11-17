class AddMissingColumnsToTaskSessionsAndDependencies < ActiveRecord::Migration[8.0]
  def change
    # Add missing columns to task_sessions
    add_column :task_sessions, :completed_at, :datetime unless column_exists?(:task_sessions, :completed_at)
    add_column :task_sessions, :error_message, :text unless column_exists?(:task_sessions, :error_message)
    
    # Add missing columns to task_dependencies based on original spec
    add_column :task_dependencies, :dependency_type, :string, default: 'blocking', null: false unless column_exists?(:task_dependencies, :dependency_type)
    add_column :task_dependencies, :status, :string, default: 'pending', null: false unless column_exists?(:task_dependencies, :status)
    
    # Add indexes
    add_index :task_dependencies, :status unless index_exists?(:task_dependencies, :status)
    add_index :task_dependencies, :dependency_type unless index_exists?(:task_dependencies, :dependency_type)
  end
end