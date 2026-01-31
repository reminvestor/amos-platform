# frozen_string_literal: true

class AddCamelSecurityFields < ActiveRecord::Migration[8.0]
  def change
    # Add Q-LLM toggle to entities
    add_column :entities, :quarantine_llm_enabled, :boolean, default: false
    
    # Add tool-specific fields to policy_rules
    # (entity_id already exists, just need tool-specific index)
    add_index :policy_rules, [:entity_id, :resource_type, :resource_id], 
              name: 'idx_policy_rules_tool_lookup',
              where: "resource_type = 'Tool'"
    
    # Add pending_tool_confirmations table for storing actions awaiting user confirmation
    create_table :pending_tool_confirmations do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :confirmation_id, null: false
      t.string :tool_name, null: false
      t.string :status, default: 'pending' # pending, confirmed, denied, expired
      t.jsonb :tool_args, default: {}
      t.jsonb :data_sources, default: []
      t.string :action_description
      t.string :reason
      t.string :session_id
      t.datetime :expires_at
      t.datetime :resolved_at
      t.timestamps
    end
    
    add_index :pending_tool_confirmations, :confirmation_id, unique: true
    add_index :pending_tool_confirmations, [:entity_id, :status]
    add_index :pending_tool_confirmations, [:session_id, :status]
    add_index :pending_tool_confirmations, :expires_at
  end
end
