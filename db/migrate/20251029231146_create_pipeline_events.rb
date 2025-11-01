class CreatePipelineEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :pipeline_events do |t|
      # Parent pipeline execution
      t.references :pipeline_execution, null: false, foreign_key: true, index: true

      # Event classification
      t.string :event_type, null: false  # ticket.intake, pr.opened, cua.dev_passed, etc.

      # Event data (schema defined in spec)
      t.jsonb :payload, default: {}

      # Event source
      t.string :source, null: false  # jira, github, agent, human, system

      # Processing status for event bus pattern
      t.boolean :processed, default: false, null: false

      t.timestamps
    end

    # Indexes for event bus and audit queries
    add_index :pipeline_events, :event_type
    add_index :pipeline_events, :processed
    add_index :pipeline_events, [:pipeline_execution_id, :event_type]
    add_index :pipeline_events, [:processed, :created_at]
    add_index :pipeline_events, :source
  end
end
