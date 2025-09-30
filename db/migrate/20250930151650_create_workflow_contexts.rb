class CreateWorkflowContexts < ActiveRecord::Migration[8.0]
  def change
    create_table :workflow_contexts do |t|
      t.references :workflow_execution, null: false, foreign_key: true
      t.references :task_session, null: false, foreign_key: true
      t.string :key, null: false
      t.jsonb :value, default: {}
      t.string :data_type, null: false
      t.jsonb :metadata, default: {}
      t.timestamps
    end
    
    add_index :workflow_contexts, :key
    add_index :workflow_contexts, :data_type
    add_index :workflow_contexts, [:workflow_execution_id, :key]
  end
end
