# frozen_string_literal: true

class AddAgentPluginToRagStores < ActiveRecord::Migration[8.0]
  def change
    # Add agent_plugin_id to rag_stores for agent-specific knowledge bases
    add_reference :rag_stores, :agent_plugin, null: true, foreign_key: true

    # Add store type for agent knowledge bases
    # Existing types: 'system', 'entity'
    # New type: 'agent' for agent-specific knowledge
    
    # Add index for quick lookups
    add_index :rag_stores, [:agent_plugin_id, :status], where: "agent_plugin_id IS NOT NULL"
  end
end
