class CreateAgentTaskProposals < ActiveRecord::Migration[7.1]
  def change
    create_table :agent_task_proposals do |t|
      # Who is involved
      t.references :proposing_agent, foreign_key: { to_table: :agent_plugins }, null: true # null = Amos/Scout
      t.references :receiving_agent, foreign_key: { to_table: :agent_plugins }, null: false
      t.references :entity, foreign_key: true, null: false
      t.references :user, foreign_key: true, null: true
      
      # Proposal details
      t.string :status, null: false, default: 'proposed' # proposed, accepted, rejected, expired, executing, completed, failed
      t.text :task_description, null: false
      t.string :task_type # update_record, fix_module, create_tool, research, etc.
      t.jsonb :required_capabilities, default: []
      t.jsonb :object_types, default: []  # What object types are involved
      t.jsonb :tools_needed, default: []  # Tools likely needed
      t.jsonb :context, default: {}       # Additional context for evaluation
      
      # Evaluation results (from receiving agent)
      t.boolean :accepted
      t.float :confidence           # 0.0 - 1.0 how confident the agent is
      t.text :rejection_reason
      t.jsonb :missing_capabilities, default: []
      t.jsonb :missing_tools, default: []
      t.jsonb :suggested_alternatives, default: [] # Other agents that might help
      t.jsonb :evaluation_details, default: {}     # Full evaluation results
      
      # Execution tracking
      t.datetime :proposed_at
      t.datetime :evaluated_at
      t.datetime :accepted_at
      t.datetime :rejected_at
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :failed_at
      t.datetime :expires_at
      
      # Link to actual execution
      t.references :agent_work_item, foreign_key: true, null: true
      t.references :agent_plugin_execution, foreign_key: true, null: true
      
      # Outcome tracking (for learning)
      t.boolean :task_succeeded
      t.text :failure_reason
      t.jsonb :outcome_metrics, default: {} # tokens_used, duration_ms, tools_called, etc.
      
      t.timestamps
    end
    
    # Indexes for common queries
    add_index :agent_task_proposals, :status
    add_index :agent_task_proposals, :task_type
    add_index :agent_task_proposals, [:receiving_agent_id, :status]
    add_index :agent_task_proposals, [:proposing_agent_id, :status]
    add_index :agent_task_proposals, [:entity_id, :created_at]
    add_index :agent_task_proposals, :accepted
    add_index :agent_task_proposals, :task_succeeded
  end
end





