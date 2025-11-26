class CreateToolUsageMetrics < ActiveRecord::Migration[8.0]
  def change
    create_table :tool_usage_metrics do |t|
      t.string :tool_name, null: false
      t.references :user, foreign_key: true
      t.references :entity, foreign_key: true
      t.references :tool_definition, foreign_key: true, null: true  # For dynamic tools
      t.string :tool_type  # class, definition, integration
      t.boolean :success, default: true
      t.integer :latency_ms
      t.jsonb :metadata, default: {}
      t.string :context  # main_chat, agent_plugin, workflow
      t.string :agent_slug  # Which agent used this tool (if applicable)

      t.timestamps
    end

    add_index :tool_usage_metrics, :tool_name
    add_index :tool_usage_metrics, [:entity_id, :tool_name]
    add_index :tool_usage_metrics, [:user_id, :tool_name]
    add_index :tool_usage_metrics, :created_at
    add_index :tool_usage_metrics, [:tool_name, :success]
  end
end
