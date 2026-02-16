# frozen_string_literal: true

class AddBountyGroomingAndWorkingMemory < ActiveRecord::Migration[8.0]
  def change
    # ═══════════════════════════════════════════════════════════════════════════
    # BOUNTY GROOMING FIELDS
    # Support sprint-style prioritization and demand-based point adjustment
    # ═══════════════════════════════════════════════════════════════════════════

    add_column :bounties, :priority_rank, :integer            # Computed rank within entity (1 = highest)
    add_column :bounties, :strategic_score, :integer          # 1-10, alignment with platform goals
    add_column :bounties, :demand_multiplier, :decimal, precision: 4, scale: 2, default: 1.0
    add_column :bounties, :original_points, :integer          # Points before demand adjustment
    add_column :bounties, :last_groomed_at, :datetime         # When AMOS last reviewed this bounty
    add_column :bounties, :grooming_notes, :text              # Why AMOS adjusted it
    add_column :bounties, :sprint_label, :string              # e.g. "Sprint 12", "Q1-Infrastructure"
    add_column :bounties, :blocked_by_ids, :jsonb, default: [] # IDs of bounties that block this one
    add_column :bounties, :tags, :jsonb, default: []          # Flexible tagging for grouping

    add_index :bounties, :priority_rank
    add_index :bounties, :sprint_label
    add_index :bounties, :last_groomed_at

    # ═══════════════════════════════════════════════════════════════════════════
    # AMOS WORKING MEMORY
    # Persistent thought continuity between thinking sessions.
    # This is the "train of thought" that carries across sessions —
    # not conversation history, but AMOS's own internal state.
    # ═══════════════════════════════════════════════════════════════════════════

    create_table :amos_working_memories do |t|
      t.references :entity, null: false, foreign_key: true

      # What AMOS is currently thinking about
      t.string :thought_type, null: false       # 'observation', 'hypothesis', 'concern', 'curiosity', 'goal', 'insight'
      t.string :topic, null: false               # Short label: "skill_evolution_effectiveness", "user_onboarding_friction"
      t.text :content, null: false               # The actual thought content
      t.float :salience, default: 0.5            # 0.0-1.0, how important/urgent this thought is right now
      t.float :confidence, default: 0.5          # 0.0-1.0, how sure AMOS is about this
      t.string :status, default: 'active'        # 'active', 'resolved', 'archived', 'superseded'

      # Continuity tracking
      t.integer :times_revisited, default: 0     # How often AMOS has come back to this thought
      t.datetime :first_thought_at               # When AMOS first had this thought
      t.datetime :last_revisited_at              # Last time AMOS considered this
      t.datetime :resolved_at                    # When this thought was resolved/addressed

      # Connections to other thoughts and actions
      t.bigint :parent_thought_id                # Thought that spawned this one
      t.jsonb :related_thought_ids, default: []  # Other connected thoughts
      t.jsonb :evidence, default: []             # Data points supporting this thought
      t.jsonb :actions_taken, default: []        # What AMOS did about this thought
      t.jsonb :metadata, default: {}             # Flexible additional data

      t.timestamps
    end

    add_index :amos_working_memories, [:entity_id, :status]
    add_index :amos_working_memories, [:entity_id, :thought_type]
    add_index :amos_working_memories, [:entity_id, :salience]
    add_index :amos_working_memories, :topic

    # ═══════════════════════════════════════════════════════════════════════════
    # AMOS ATTENTION LOG
    # Records what AMOS chose to focus on and why — meta-cognition breadcrumbs
    # ═══════════════════════════════════════════════════════════════════════════

    create_table :amos_attention_logs do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :amos_thinking_session, foreign_key: true

      t.string :focus_area, null: false          # What AMOS decided to focus on
      t.text :reasoning                          # Why it chose this over alternatives
      t.jsonb :alternatives_considered, default: [] # What else it could have focused on
      t.jsonb :signals, default: []              # What triggered this attention shift
      t.string :outcome                          # 'acted', 'deferred', 'delegated', 'noted'
      t.text :outcome_notes                      # What happened as a result
      t.integer :token_cost, default: 0          # Tokens spent on this focus area
      t.integer :duration_ms, default: 0         # Time spent

      t.timestamps
    end

    add_index :amos_attention_logs, [:entity_id, :created_at]
  end
end
