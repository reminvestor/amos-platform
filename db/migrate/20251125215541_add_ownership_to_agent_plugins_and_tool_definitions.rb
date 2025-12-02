class AddOwnershipToAgentPluginsAndToolDefinitions < ActiveRecord::Migration[8.0]
  def change
    # Add user_id to agent_plugins for ownership tracking
    # This allows us to track who created the agent and enforce edit permissions
    add_reference :agent_plugins, :user, foreign_key: true, null: true

    # Add entity_id to tool_definitions for multi-tenancy
    # This allows tools to be scoped to a specific entity/organization
    add_reference :tool_definitions, :entity, foreign_key: true, null: true

    # Add index for faster lookups
    add_index :agent_plugins, [:entity_id, :user_id]
  end
end
