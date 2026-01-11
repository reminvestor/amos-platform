# frozen_string_literal: true

class CreateModuleIntegrations < ActiveRecord::Migration[8.0]
  def change
    create_table :module_integrations do |t|
      t.references :app_module, null: false, foreign_key: true
      t.references :integration, null: false, foreign_key: true
      t.string :purpose, null: false  # e.g., 'publishing', 'analytics', 'sync'
      t.string :status, default: 'required'  # required, optional, connected, disconnected
      t.text :description  # Why this integration is needed
      t.jsonb :config, default: {}  # Integration-specific config for this module
      t.boolean :is_critical, default: false  # If true, module can't function without it
      t.datetime :connected_at
      t.datetime :last_used_at
      
      t.timestamps
    end

    add_index :module_integrations, [:app_module_id, :integration_id], unique: true
    add_index :module_integrations, :status
    add_index :module_integrations, :is_critical
  end
end

