# frozen_string_literal: true

class ExtendDesignPlansForApps < ActiveRecord::Migration[7.1]
  def change
    # Add data_sources for binding workflow outputs to design components
    unless column_exists?(:design_plans, :data_sources)
      add_column :design_plans, :data_sources, :jsonb, default: [], null: false
    end
    
    # Add app reference for when design plan builds an app
    unless column_exists?(:design_plans, :app_id)
      add_reference :design_plans, :app, foreign_key: true, null: true
    end
    
    # Add module_canvas reference for canvas-type plans
    unless column_exists?(:design_plans, :module_canvas_id)
      add_reference :design_plans, :module_canvas, foreign_key: { to_table: :module_canvases }, null: true
    end
    
    # Add index for data_sources queries (only if column exists and index doesn't)
    if column_exists?(:design_plans, :data_sources) && !index_exists?(:design_plans, :data_sources)
      add_index :design_plans, :data_sources, using: :gin
    end
  end
end
