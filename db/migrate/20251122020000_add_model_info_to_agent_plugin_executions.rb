class AddModelInfoToAgentPluginExecutions < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_plugin_executions, :model_id, :string, if_not_exists: true
    add_column :agent_plugin_executions, :model_input_tokens, :integer, default: 0, if_not_exists: true
    add_column :agent_plugin_executions, :model_output_tokens, :integer, default: 0, if_not_exists: true
  end
end
