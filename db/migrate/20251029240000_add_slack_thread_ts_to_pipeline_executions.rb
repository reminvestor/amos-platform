class AddSlackThreadTsToPipelineExecutions < ActiveRecord::Migration[8.0]
  def change
    add_column :pipeline_executions, :slack_thread_ts, :string
    add_index :pipeline_executions, :slack_thread_ts
  end
end
