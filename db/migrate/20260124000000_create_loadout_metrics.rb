# frozen_string_literal: true

class CreateLoadoutMetrics < ActiveRecord::Migration[8.0]
  def change
    create_table :loadout_metrics do |t|
      t.string :loadout_slug, null: false
      t.references :entity, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :canvas_context
      t.string :event_type, null: false  # 'success', 'failure', 'hallucination', 'tool_call', 'tool_error'
      t.jsonb :details, default: {}
      t.float :quality_score
      t.integer :response_time_ms
      t.string :session_id
      t.timestamps
    end

    add_index :loadout_metrics, [:loadout_slug, :created_at]
    add_index :loadout_metrics, [:entity_id, :loadout_slug]
    add_index :loadout_metrics, [:entity_id, :event_type, :created_at]
    add_index :loadout_metrics, :canvas_context
  end
end
