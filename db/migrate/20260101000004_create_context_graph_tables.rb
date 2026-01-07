# frozen_string_literal: true

class CreateContextGraphTables < ActiveRecord::Migration[7.2]
  def change
    # ═══════════════════════════════════════════════════════════════════════════
    # DECISION TRACES - The core of our context graph
    # Captures the WHY behind every agent decision
    # ═══════════════════════════════════════════════════════════════════════════
    create_table :decision_traces do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :agent_plugin, foreign_key: true
      t.references :agent_lightning_trace, foreign_key: true
      t.references :parent_decision, foreign_key: { to_table: :decision_traces }

      # Identification
      t.string :trace_id, null: false, index: { unique: true }
      
      # Decision metadata
      t.string :decision_type, null: false  # action, delegation, escalation, exception, etc.
      t.text :decision_summary, null: false
      t.text :reasoning
      
      # Context captured at decision time (THE KEY!)
      t.jsonb :context_gathered, default: {}  # All context pulled from systems
      t.jsonb :inputs_used, default: []       # List of inputs that influenced decision
      t.jsonb :policies_evaluated, default: [] # Policies checked and their results
      
      # Exception tracking
      t.boolean :is_exception, default: false
      t.text :exception_justification
      
      # Approval chain
      t.boolean :requires_approval, default: false
      t.string :approval_status  # pending, approved, rejected, auto_approved
      t.string :approved_by      # User email or agent slug
      t.datetime :approved_at
      t.text :approval_notes
      
      # Outcome tracking
      t.string :outcome          # success, failure, partial, unknown
      t.jsonb :outcome_details, default: {}
      t.decimal :outcome_quality_score, precision: 5, scale: 4
      t.datetime :outcome_recorded_at
      
      # Confidence
      t.decimal :confidence_score, precision: 5, scale: 4
      
      # Vector embedding for similarity search
      t.vector :embedding, limit: 1536
      
      # Additional metadata
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end

    # Indexes for common queries
    add_index :decision_traces, [:entity_id, :decision_type]
    add_index :decision_traces, [:entity_id, :created_at]
    add_index :decision_traces, [:entity_id, :is_exception]
    add_index :decision_traces, [:entity_id, :outcome]
    add_index :decision_traces, [:agent_plugin_id, :created_at]
    add_index :decision_traces, :approval_status

    # ═══════════════════════════════════════════════════════════════════════════
    # DECISION PRECEDENTS - Links decisions to their precedents
    # The "edges" in our context graph
    # ═══════════════════════════════════════════════════════════════════════════
    create_table :decision_precedents do |t|
      t.references :decision_trace, null: false, foreign_key: true
      t.references :precedent_decision, null: false, foreign_key: { to_table: :decision_traces }
      
      t.decimal :similarity_score, precision: 5, scale: 4, null: false
      t.string :influence_type, null: false  # exception_precedent, success_pattern, etc.
      t.boolean :outcome_matches  # Did the outcome match the precedent?
      
      t.timestamps
    end

    add_index :decision_precedents, [:decision_trace_id, :precedent_decision_id], 
              unique: true, name: 'idx_decision_precedent_unique'
    add_index :decision_precedents, :influence_type

    # ═══════════════════════════════════════════════════════════════════════════
    # CONTEXT GRAPH STATS - Aggregate metrics for the context graph
    # ═══════════════════════════════════════════════════════════════════════════
    create_table :context_graph_stats do |t|
      t.references :entity, null: false, foreign_key: true
      t.date :stats_date, null: false
      
      # Volume metrics
      t.integer :total_decisions, default: 0
      t.integer :decisions_with_precedents, default: 0
      t.integer :exceptions_granted, default: 0
      t.integer :approvals_pending, default: 0
      t.integer :approvals_granted, default: 0
      t.integer :approvals_rejected, default: 0
      
      # Quality metrics
      t.decimal :avg_confidence_score, precision: 5, scale: 4
      t.decimal :precedent_match_rate, precision: 5, scale: 4  # How often precedents predict outcome
      t.decimal :exception_success_rate, precision: 5, scale: 4
      
      # Graph metrics
      t.integer :unique_precedent_chains, default: 0  # Number of distinct precedent paths
      t.integer :avg_precedent_depth, default: 0      # Average depth of precedent links
      
      t.jsonb :decision_type_breakdown, default: {}
      t.jsonb :top_precedents, default: []  # Most frequently used precedents
      
      t.timestamps
    end

    add_index :context_graph_stats, [:entity_id, :stats_date], unique: true
  end
end

