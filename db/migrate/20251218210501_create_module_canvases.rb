# frozen_string_literal: true

class CreateModuleCanvases < ActiveRecord::Migration[8.0]
  def change
    create_table :module_canvases do |t|
      t.references :app_module, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      
      # Canvas identification
      t.string :slug, null: false  # inventory_overview, product_list, etc.
      t.string :name, null: false
      t.text :description
      
      # Canvas type and mode
      t.string :canvas_type, default: 'module'  # module, dashboard, data_grid, form, report
      t.string :ui_mode, default: 'simple'      # simple, advanced
      
      # Content - the actual HTML/JS for the canvas
      t.text :html_content       # The HTML template
      t.text :js_content         # Stimulus controller or vanilla JS
      t.text :css_content        # Custom styles (optional)
      
      # Data binding - what data this canvas needs
      t.jsonb :data_sources, default: []
      # [
      #   { type: 'model', model: 'Product', scope: 'all', limit: 100 },
      #   { type: 'tool', tool: 'get_inventory_stats' }
      # ]
      
      # Actions available on this canvas
      t.jsonb :actions, default: []
      # [
      #   { name: 'add_product', tool: 'create_product', icon: 'plus' },
      #   { name: 'export', tool: 'export_inventory', icon: 'download' }
      # ]
      
      # Layout configuration
      t.jsonb :layout_config, default: {}
      # {
      #   columns: 3,
      #   show_header: true,
      #   show_search: true,
      #   show_filters: true
      # }
      
      # Versioning
      t.integer :version, default: 1
      t.text :previous_versions  # JSON array of previous versions
      
      t.boolean :is_default, default: false  # Default canvas for this module
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end

    add_index :module_canvases, [:app_module_id, :slug], unique: true
    add_index :module_canvases, [:entity_id, :slug]
    add_index :module_canvases, :canvas_type
    add_index :module_canvases, :ui_mode
  end
end





