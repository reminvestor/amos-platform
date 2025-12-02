class AddScoutAccessibleToToolDefinitions < ActiveRecord::Migration[8.0]
  def change
    # For dynamic tools (ToolDefinition records)
    add_column :tool_definitions, :scout_accessible, :boolean, default: false
    add_index :tool_definitions, :scout_accessible

    # Also add to the tools metadata table if we want to track class tools
    # For now, class tools will have a separate configuration
  end
end
