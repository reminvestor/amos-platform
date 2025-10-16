class CreateAnalyticsQueryLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :analytics_query_logs do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :metric_definition, null: false, foreign_key: true
      t.string :metric_name
      t.string :query_hash
      t.jsonb :query_params
      t.text :compiled_query
      t.integer :rows_returned
      t.integer :execution_time_ms
      t.boolean :success
      t.text :error_message
      t.jsonb :metadata

      t.timestamps
    end
  end
end
