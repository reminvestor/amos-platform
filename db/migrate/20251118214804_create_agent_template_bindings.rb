class CreateAgentTemplateBindings < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_template_bindings do |t|
      t.references :workflow_template, null: false, foreign_key: true, index: true
      t.references :agent_plugin, null: false, foreign_key: true, index: true
      t.string :phase  # gather_context, execute_goal, validate_result
      t.boolean :required, default: false
      t.integer :execution_order, default: 0

      t.timestamps
    end

    add_index :agent_template_bindings, [:workflow_template_id, :phase]
    add_index :agent_template_bindings, [:workflow_template_id, :agent_plugin_id, :phase],
              unique: true, name: 'index_agent_template_bindings_unique'
  end
end
