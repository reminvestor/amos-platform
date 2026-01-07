# frozen_string_literal: true

class AddMetricsSnapshotToPlatformPerceptions < ActiveRecord::Migration[7.2]
  def change
    # Add metrics_snapshot to store the raw metrics data
    add_column :platform_perceptions, :metrics_snapshot, :jsonb, default: {}
  end
end


