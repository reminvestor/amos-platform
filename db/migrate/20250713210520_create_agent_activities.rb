class CreateAgentActivities < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_activities do |t|
      t.references :conversation, null: false, foreign_key: { to_table: :scout_conversations }
      t.string :agent_name
      t.string :activity_type
      t.jsonb :input_data
      t.jsonb :output_data
      t.integer :processing_time_ms

      t.timestamps
    end
  end
end
