# frozen_string_literal: true

class AddSpacesToAgentPlugins < ActiveRecord::Migration[8.0]
  def change
    # Add spaces array - which spaces this agent is available in
    # Values: 'personal', 'work', 'team' (matches SpaceDefinition slugs)
    # Empty array or nil means available in all spaces (default/legacy behavior)
    add_column :agent_plugins, :spaces, :string, array: true, default: []
    
    # Add index for filtering by space
    add_index :agent_plugins, :spaces, using: 'gin'
  end
end
