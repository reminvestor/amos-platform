# frozen_string_literal: true

class EnhanceModuleConfiguration < ActiveRecord::Migration[7.0]
  def change
    # Enhance app_modules with rich configuration
    add_column :app_modules, :field_config, :jsonb, default: {}
    # Stores enhanced field definitions with:
    # - section: 'content' | 'scheduling' | 'workflow' | 'metrics' | 'advanced'
    # - visibility: 'always' | 'create_only' | 'edit_only' | 'read_only' | 'system'
    # - show_when: { field: 'status', equals: 'published' }
    # - ui_component: 'rich_text_editor' | 'media_gallery' | 'datetime_picker' | etc.
    # - ai_assist: true/false
    # - order: integer
    
    add_column :app_modules, :action_config, :jsonb, default: []
    # Quick reference to module_actions, can include inline actions too
    
    add_column :app_modules, :tool_config, :jsonb, default: []
    # Auto-generated tool definitions for this module
    
    add_column :app_modules, :relationship_config, :jsonb, default: []
    # Relationships with other modules:
    # - type: 'belongs_to' | 'has_many' | 'has_one' | 'many_to_many'
    # - target: 'campaigns'
    # - foreign_key: 'campaign_id'
    
    add_column :app_modules, :is_primary, :boolean, default: false
    # Is this the main/primary module in the app?
    
    # Enhance module_canvases with layout configuration
    add_column :module_canvases, :layout, :string, default: 'default'
    # default, single_column, two_column, tabbed, wizard, sidebar
    
    add_column :module_canvases, :sections, :jsonb, default: []
    # For form layouts:
    # [{ name: 'Content', icon: 'edit', fields: ['title', 'content'] }]
    
    add_column :module_canvases, :tabs, :jsonb, default: []
    # For tabbed layouts:
    # [{ name: 'Content', icon: 'edit', sections: ['content', 'media'] }]
    
    add_column :module_canvases, :filters, :jsonb, default: []
    # For list views: ['status', 'platforms', 'created_at']
    
    add_column :module_canvases, :sorting, :jsonb, default: []
    # For list views: [{ field: 'created_at', direction: 'desc' }]
    
    add_column :module_canvases, :columns, :jsonb, default: []
    # For list views: ['title', 'status', 'scheduled_for']
    
    add_column :module_canvases, :card_config, :jsonb, default: {}
    # For kanban/calendar: { title: 'title', subtitle: 'platforms', color: 'status' }
    
    # Only add actions column if it doesn't exist
    unless column_exists?(:module_canvases, :actions)
      add_column :module_canvases, :actions, :jsonb, default: []
    end
    
    add_index :module_canvases, :layout unless index_exists?(:module_canvases, :layout)
  end
end

