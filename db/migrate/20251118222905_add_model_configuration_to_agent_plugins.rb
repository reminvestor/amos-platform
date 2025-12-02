class AddModelConfigurationToAgentPlugins < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_plugins, :model_name, :string, default: 'claude-sonnet-4'
    add_column :agent_plugins, :model_config, :jsonb, default: {}

    # Add index for querying by model
    add_index :agent_plugins, :model_name
  end
end
