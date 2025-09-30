class CreateWorkflowExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :workflow_executions do |t|
      t.references :task_session, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.string :workflow_template_id
      t.jsonb :workflow_spec, default: {}
      t.string :status, null: false, default: 'pending'
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :workflow_executions, :status
    add_index :workflow_executions, :workflow_template_id
    add_index :workflow_executions, [:entity_id, :status]
    add_index :workflow_executions, :created_at
  end
end
