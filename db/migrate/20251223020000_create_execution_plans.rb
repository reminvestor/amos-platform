class CreateExecutionPlans < ActiveRecord::Migration[7.1]
  def change
    create_table :execution_plans do |t|
      t.references :entity, foreign_key: true, null: false
      t.references :user, foreign_key: true, null: false
      t.references :created_by_agent, foreign_key: { to_table: :agent_plugins }, null: true
      
      # Plan metadata
      t.string :title, null: false
      t.text :original_request, null: false
      t.text :summary
      t.string :status, null: false, default: 'planning' # planning, ready, executing, paused, completed, failed, cancelled
      t.string :complexity, default: 'medium' # simple, medium, complex, epic
      
      # Plan structure (JSONB for flexibility)
      t.jsonb :phases, default: []          # Array of phases with steps
      t.jsonb :dependencies, default: {}     # Step dependencies
      t.jsonb :agent_assignments, default: {} # Which agent handles each step
      t.jsonb :validation_results, default: {} # Handshake results per step
      
      # Execution tracking
      t.integer :total_steps, default: 0
      t.integer :completed_steps, default: 0
      t.integer :failed_steps, default: 0
      t.integer :current_phase, default: 0
      t.string :current_step_id
      t.jsonb :step_results, default: {}    # Results from each completed step
      t.jsonb :execution_log, default: []   # Timeline of events
      
      # User interaction
      t.boolean :requires_approval, default: false
      t.boolean :approved, default: false
      t.datetime :approved_at
      t.jsonb :user_decisions, default: {}  # Decisions made during execution
      
      # Timing
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :failed_at
      t.integer :estimated_duration_minutes
      t.integer :actual_duration_minutes
      
      # Error handling
      t.text :failure_reason
      t.jsonb :blocked_by, default: []      # Steps blocking progress
      t.integer :retry_count, default: 0
      
      t.timestamps
    end

    add_index :execution_plans, :status
    add_index :execution_plans, [:entity_id, :status]
    add_index :execution_plans, [:user_id, :created_at]
    add_index :execution_plans, :complexity
  end
end





