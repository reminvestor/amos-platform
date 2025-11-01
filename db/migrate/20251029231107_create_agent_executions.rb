class CreateAgentExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_executions do |t|
      # Parent pipeline execution
      t.references :pipeline_execution, null: false, foreign_key: true, index: true

      # Agent identification
      t.string :agent_id, null: false  # clarifier, planner, coder, reviewer, cua_pack

      # Execution status
      t.integer :status, null: false, default: 0  # 0=pending, 1=running, 2=completed, 3=failed

      # Workspace isolation
      t.string :workspace_path  # /tmp/pipeline-{execution_id}/{agent_id}

      # Input/output data
      t.jsonb :inputs, default: {}  # Input data passed to agent
      t.jsonb :outputs, default: {}  # Results from agent execution

      # Execution logs and errors
      t.text :logs  # Execution logs
      t.text :error_message  # Error details if failed

      # Cost tracking
      t.integer :tokens_used, default: 0
      t.decimal :cost, precision: 10, scale: 4, default: 0.0

      # Timing
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    # Indexes for common queries
    add_index :agent_executions, :agent_id
    add_index :agent_executions, :status
    add_index :agent_executions, [:pipeline_execution_id, :agent_id]
    add_index :agent_executions, [:pipeline_execution_id, :status]
    add_index :agent_executions, :started_at
  end
end
