class CreateAgentCapabilities < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_capabilities do |t|
      t.references :agent_plugin, null: false, foreign_key: true, index: true
      t.string :capability_name, null: false
      t.jsonb :contract_schema, default: {}
      t.text :implementation_notes

      t.timestamps
    end

    # Ensure unique capability names per agent
    add_index :agent_capabilities, [:agent_plugin_id, :capability_name], unique: true, name: 'index_agent_capabilities_on_plugin_and_name'
    add_index :agent_capabilities, :capability_name
  end
end
