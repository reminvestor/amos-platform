# frozen_string_literal: true

class CreatePlatformCosts < ActiveRecord::Migration[8.0]
  def change
    create_table :platform_costs do |t|
      t.string :category, null: false  # compute, infrastructure, third_party, personnel, other
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :description
      t.datetime :recorded_at, null: false
      t.string :period_type, default: 'one_time'  # one_time, monthly, annual
      t.date :period_start
      t.date :period_end
      t.jsonb :metadata, default: {}
      t.references :recorded_by, foreign_key: { to_table: :users }, null: true
      
      t.timestamps
    end
    
    add_index :platform_costs, :category
    add_index :platform_costs, :recorded_at
    add_index :platform_costs, [:period_start, :period_end]
  end
end
