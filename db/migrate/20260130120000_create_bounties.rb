# frozen_string_literal: true

class CreateBounties < ActiveRecord::Migration[7.1]
  def change
    create_table :bounties do |t|
      # Core fields
      t.string :title, null: false
      t.text :description
      t.string :bounty_type, null: false  # bug, feature, content, marketing, documentation, support
      t.integer :points, null: false, default: 0
      t.string :status, default: 'open'   # open, claimed, in_progress, submitted, reviewing, approved, rejected, expired

      # Relationships
      t.references :entity, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }, null: true  # null = created by AMOS
      t.references :claimed_by, foreign_key: { to_table: :users }, null: true
      t.references :reviewed_by, foreign_key: { to_table: :users }, null: true
      t.references :support_ticket, foreign_key: true, null: true  # Link to existing ticket if applicable

      # AI scoring metadata
      t.text :ai_scoring_rationale     # Why AMOS assigned these points
      t.float :estimated_hours         # AI estimate of effort
      t.integer :impact_score          # 1-10 scale
      t.integer :urgency_score         # 1-10 scale
      t.integer :complexity_score      # 1-10 scale

      # Work tracking
      t.datetime :claimed_at
      t.datetime :submitted_at
      t.datetime :approved_at
      t.datetime :rejected_at
      t.datetime :expires_at           # Bounties can expire
      t.text :submission_notes         # What the contributor submitted
      t.text :review_notes             # Reviewer feedback
      t.integer :final_points          # May differ from original after review

      # Source tracking
      t.string :source                 # amos_thinking, user_submitted, log_monitor, feature_vote
      t.jsonb :metadata, default: {}   # Additional context

      # Voting (for feature bounties)
      t.integer :upvotes, default: 0
      t.integer :downvotes, default: 0

      t.timestamps
    end

    add_index :bounties, :status
    add_index :bounties, :bounty_type
    add_index :bounties, :source
    add_index :bounties, :points
    add_index :bounties, [:status, :bounty_type]
    add_index :bounties, [:entity_id, :status]
  end
end
