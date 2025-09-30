class CreateWorkflowVariables < ActiveRecord::Migration[8.0]
  def change
    create_table :workflow_variables do |t|
      t.references :workflow_execution, null: false, foreign_key: true
      t.references :source, polymorphic: true, null: true
      t.string :name, null: false
      t.jsonb :value
      t.string :data_type
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :workflow_variables, :name
    add_index :workflow_variables, [:workflow_execution_id, :name], unique: true, name: 'idx_workflow_var_unique'
    add_index :workflow_variables, [:source_type, :source_id]
  end
end
