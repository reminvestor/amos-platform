class CreateToolDefinitionsAndExtendAgents < ActiveRecord::Migration[8.0]
  def change
    # 1. Create ToolDefinition table for dynamic DB-based tools
    create_table :tool_definitions do |t|
      t.string :name, null: false
      t.text :description
      t.jsonb :parameters, default: {}
      t.string :execution_type, default: 'ruby_code' # ruby_code, http_request
      t.text :code # For ruby_code type
      t.jsonb :api_config, default: {} # For http_request type { url: '...', method: 'POST' }
      t.boolean :admin_only, default: false
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      
      t.timestamps
    end
    
    add_index :tool_definitions, :name, unique: true

    # 2. Extend AgentPlugin for "Proxy/Remote" architecture
    add_column :agent_plugins, :execution_strategy, :string, default: 'standard' # standard, workflow, remote_http
    add_column :agent_plugins, :remote_config, :jsonb, default: {}
    
    # Add index for strategy
    add_index :agent_plugins, :execution_strategy
  end
end

