# frozen_string_literal: true

class ExtendDesignPlansForApps < ActiveRecord::Migration[7.1]
  def change
    # Add data_sources for binding workflow outputs to design components
    add_column :design_plans, :data_sources, :jsonb, default: [], null: false
    
    # Add app reference for when design plan builds an app
    add_reference :design_plans, :app, foreign_key: true
    
    # Add module_canvas reference for canvas-type plans
    add_reference :design_plans, :module_canvas, foreign_key: { to_table: :module_canvases }
    
    # Add index for data_sources queries
    add_index :design_plans, :data_sources, using: :gin
  end
end
