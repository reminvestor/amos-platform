class CreateAgentPluginExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_plugin_executions do |t|
      t.references :agent_plugin, null: false, foreign_key: true, index: true
      t.references :workflow_execution, null: true, foreign_key: true, index: true
      t.references :user, null: false, foreign_key: true, index: true
      t.string :status, default: "running", null: false  # running, completed, failed
      t.jsonb :input_context, default: {}
      t.jsonb :output_result, default: {}
      t.integer :duration_ms
      t.integer :tokens_used, default: 0
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    # Indexes for analytics and querying
    add_index :agent_plugin_executions, :status
    add_index :agent_plugin_executions, :started_at
    add_index :agent_plugin_executions, [:agent_plugin_id, :status]
    add_index :agent_plugin_executions, [:user_id, :created_at]
  end
end
