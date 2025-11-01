class AddUniqueIndexToPipelineExecutions < ActiveRecord::Migration[8.0]
  def change
    # Remove existing non-unique index on ticket_id
    remove_index :pipeline_executions, :ticket_id

    # Add unique composite index to prevent duplicate pipeline executions for the same ticket
    # This ensures one pipeline per ticket per entity/connection combination
    add_index :pipeline_executions,
              [:entity_id, :ticket_id, :mcp_connection_id],
              unique: true,
              name: 'index_pipeline_executions_on_unique_ticket'
  end
end
