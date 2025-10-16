class CreateWorkflowStepExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :workflow_step_executions do |t|
      t.references :workflow_execution, null: false, foreign_key: true
      t.string :step_id, null: false
      t.string :step_name
      t.string :step_type
      t.string :status, null: false, default: 'pending'
      t.datetime :started_at
      t.datetime :completed_at
      t.jsonb :input_data, default: {}
      t.jsonb :output_data, default: {}
      t.text :error_message
      t.integer :retry_count, default: 0
      t.string :agent_id

      t.timestamps
    end

    add_index :workflow_step_executions, :step_id
    add_index :workflow_step_executions, :status
    add_index :workflow_step_executions, [ :workflow_execution_id, :step_id ], unique: true, name: 'idx_workflow_step_unique'
    add_index :workflow_step_executions, [ :workflow_execution_id, :status ], name: 'idx_workflow_step_status'
  end
end
