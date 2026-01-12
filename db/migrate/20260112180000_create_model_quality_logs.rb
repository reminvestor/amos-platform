# frozen_string_literal: true

class CreateModelQualityLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :model_quality_logs do |t|
      t.string :model_id, null: false
      t.string :event_type, null: false # json_parse_error, tool_success, tool_failure, fallback_triggered
      t.string :tool_name
      t.text :details
      t.references :entity, foreign_key: true
      t.references :user, foreign_key: true
      t.string :session_id
      t.float :latency_ms # For performance tracking
      t.boolean :fallback_used, default: false
      t.string :fallback_model_id # If a fallback was used, which model
      
      t.timestamps
    end
    
    add_index :model_quality_logs, :model_id
    add_index :model_quality_logs, :event_type
    add_index :model_quality_logs, :created_at
    add_index :model_quality_logs, [:model_id, :event_type]
    add_index :model_quality_logs, [:model_id, :tool_name]
  end
end

