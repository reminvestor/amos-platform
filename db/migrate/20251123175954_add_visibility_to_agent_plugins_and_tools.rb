class AddVisibilityToAgentPluginsAndTools < ActiveRecord::Migration[8.0]
  def change
    # Agent Plugins
    add_column :agent_plugins, :is_public, :boolean, default: false
    add_column :agent_plugins, :published_at, :datetime

    # Tool Definitions
    add_column :tool_definitions, :is_public, :boolean, default: false
    add_column :tool_definitions, :published_at, :datetime
  end
end
