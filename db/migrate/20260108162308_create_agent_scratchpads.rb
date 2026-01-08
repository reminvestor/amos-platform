# frozen_string_literal: true

class CreateAgentScratchpads < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_scratchpads do |t|
      # Core ownership
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      
      # Session scoping - critical for agent data sharing
      t.string :session_id, null: false
      
      # Data storage
      t.string :key, null: false
      t.jsonb :data, default: {}
      t.string :data_type  # research_data, intermediate_result, handoff_data, working_state
      t.text :description
      
      # Source tracking
      t.references :source_agent_plugin, foreign_key: { to_table: :agent_plugins }, null: true
      t.references :source_execution, foreign_key: { to_table: :agent_plugin_executions }, null: true
      
      # Lifecycle
      t.datetime :expires_at, null: false
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    # Unique key within a session
    add_index :agent_scratchpads, [:session_id, :key], unique: true
    
    # For cleanup job
    add_index :agent_scratchpads, :expires_at
    
    # For querying by session
    add_index :agent_scratchpads, :session_id
    
    # For querying by entity
    add_index :agent_scratchpads, [:entity_id, :session_id]
  end
end
