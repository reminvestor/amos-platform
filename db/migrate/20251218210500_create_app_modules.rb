# frozen_string_literal: true

class CreateAppModules < ActiveRecord::Migration[8.0]
  def change
    create_table :app_modules do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :created_by, null: true, foreign_key: { to_table: :users }
      
      # Core identification
      t.string :slug, null: false
      t.string :name, null: false
      t.text :description
      t.string :version, default: '1.0.0'
      t.string :icon  # Lucide icon name
      
      # Status & visibility
      t.string :status, null: false, default: 'draft'  # draft, testing, active, disabled
      t.string :visibility, default: 'entity_private'  # entity_private, entity_shared, public
      t.string :author_type, default: 'amos'  # system, amos, user
      
      # Module manifest - what this module provides
      t.jsonb :components, default: {}
      # Structure:
      # {
      #   canvases: ['inventory_overview', 'product_list'],
      #   data_models: ['Product', 'InventoryLevel'],
      #   tools: ['track_inventory', 'check_stock'],
      #   agents: ['inventory_manager'],
      #   webhooks: ['stock_updated', 'low_stock_alert'],
      #   scheduled_tasks: ['daily_inventory_report']
      # }
      
      # UI mode configurations
      t.jsonb :ui_modes, default: { simple: true, advanced: false }
      # { simple: true, advanced: true, simple_default: true }
      
      # Dependencies and permissions
      t.jsonb :dependencies, default: []  # ['core', 'contacts']
      t.jsonb :permissions, default: []   # ['read_contacts', 'create_visualizations']
      
      # Menu integration
      t.boolean :show_in_menu, default: true
      t.integer :menu_order, default: 100
      t.string :menu_parent  # null = top level, or parent module slug
      
      # Metadata
      t.jsonb :metadata, default: {}
      t.datetime :deployed_at
      t.datetime :last_tested_at
      t.jsonb :test_results, default: {}
      
      t.timestamps
    end

    add_index :app_modules, [:entity_id, :slug], unique: true
    add_index :app_modules, :status
    add_index :app_modules, :visibility
    add_index :app_modules, :author_type
  end
end





