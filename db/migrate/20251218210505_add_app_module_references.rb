# frozen_string_literal: true

class AddAppModuleReferences < ActiveRecord::Migration[8.0]
  def change
    # Link existing models to app_modules
    add_reference :tool_definitions, :app_module, null: true, foreign_key: true
    add_reference :agent_plugins, :app_module, null: true, foreign_key: true
    add_reference :scheduled_agent_tasks, :app_module, null: true, foreign_key: true
    
    # Add custom_fields JSONB to core models that should support custom fields
    # Using a flexible approach - any model can have custom fields via this column
    add_column :contacts, :custom_fields, :jsonb, default: {}
    add_column :campaigns, :custom_fields, :jsonb, default: {}
    add_column :landing_pages, :custom_fields, :jsonb, default: {}
    add_column :opportunities, :custom_fields, :jsonb, default: {}
    
    # Index for custom field queries
    add_index :contacts, :custom_fields, using: :gin
    add_index :campaigns, :custom_fields, using: :gin
    add_index :landing_pages, :custom_fields, using: :gin
    add_index :opportunities, :custom_fields, using: :gin
  end
end





