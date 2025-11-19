class RenameModelNameToAiModelInAgentPlugins < ActiveRecord::Migration[8.0]
  def change
    rename_column :agent_plugins, :model_name, :ai_model
  end
end
