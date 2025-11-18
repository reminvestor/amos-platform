class CreateAgentTools < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_tools do |t|
      t.references :agent_plugin, null: false, foreign_key: true, index: true
      t.string :tool_name, null: false
      t.boolean :required, default: false

      t.timestamps
    end

    # Ensure unique tool names per agent
    add_index :agent_tools, [:agent_plugin_id, :tool_name], unique: true, name: 'index_agent_tools_on_plugin_and_tool'
    add_index :agent_tools, :tool_name
  end
end
