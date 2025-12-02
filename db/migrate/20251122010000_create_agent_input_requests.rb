class CreateAgentInputRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_input_requests do |t|
      t.references :agent_plugin_execution, null: false, foreign_key: true
      t.text :question, null: false
      t.jsonb :context_data, default: {}
      t.string :variable_name
      t.string :status, default: 'pending', null: false
      t.text :response_content
      t.datetime :responded_at

      t.timestamps
    end

    add_index :agent_input_requests, :status
    
    add_column :agent_plugin_executions, :conversation_context, :jsonb, default: []
  end
end

