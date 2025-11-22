class AddModelInfoToAgentPluginExecutions < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_plugin_executions, :model_id, :string
    add_column :agent_plugin_executions, :model_input_tokens, :integer, default: 0
    add_column :agent_plugin_executions, :model_output_tokens, :integer, default: 0
  end
end

