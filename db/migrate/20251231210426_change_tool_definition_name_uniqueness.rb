class ChangeToolDefinitionNameUniqueness < ActiveRecord::Migration[8.0]
  def change
    # Remove the global unique index on name
    remove_index :tool_definitions, :name, unique: true
    
    # Add a composite unique index scoped to entity_id
    # This allows the same tool name in different tenants
    add_index :tool_definitions, [:entity_id, :name], unique: true, name: 'index_tool_definitions_on_entity_and_name'
  end
end
