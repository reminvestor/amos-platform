class CreatePipelineExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :pipeline_executions do |t|
      # Multi-tenant scoping
      t.references :entity, null: false, foreign_key: true, index: true

      # Source ticket system connection
      t.references :mcp_connection, null: false, foreign_key: true, index: true

      # Ticket information
      t.string :ticket_id, null: false
      t.string :ticket_system, null: false  # jira, azure_devops
      t.string :ticket_url
      t.string :ticket_title, null: false
      t.text :ticket_description
      t.integer :priority, default: 2  # 0=critical, 1=high, 2=medium, 3=low
      t.jsonb :ticket_metadata, default: {}  # custom fields, labels, etc

      # Git information
      t.bigint :git_connection_id  # Reference to MCP connection for GitHub/Azure Repos
      t.string :repository
      t.string :branch_name
      t.string :pr_id
      t.string :pr_url

      # State tracking
      t.integer :status, null: false, default: 0  # See PipelineExecution model for enum
      t.jsonb :state_history, default: []  # Array of state transitions with timestamps
      t.datetime :state_changed_at

      # Cost tracking
      t.integer :total_tokens_used, default: 0
      t.decimal :total_cost, precision: 10, scale: 4, default: 0.0

      # Timing
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    # Indexes for common queries
    add_index :pipeline_executions, :ticket_id
    add_index :pipeline_executions, :ticket_system
    add_index :pipeline_executions, :status
    add_index :pipeline_executions, :priority
    add_index :pipeline_executions, [:entity_id, :status]
    add_index :pipeline_executions, [:entity_id, :ticket_system]
    add_index :pipeline_executions, :started_at
    add_index :pipeline_executions, :completed_at
    add_index :pipeline_executions, :git_connection_id

    # Foreign key for git_connection_id (references mcp_connections)
    add_foreign_key :pipeline_executions, :mcp_connections, column: :git_connection_id
  end
end
