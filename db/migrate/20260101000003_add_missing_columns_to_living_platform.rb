# frozen_string_literal: true

class AddMissingColumnsToLivingPlatform < ActiveRecord::Migration[7.2]
  def change
    # Add promotion tracking to evolution cycles
    add_column :evolution_cycles, :promotion_count, :integer, default: 0
    add_column :evolution_cycles, :anomaly_count, :integer, default: 0
    add_column :evolution_cycles, :duration_minutes, :integer, default: 0
  end
end


