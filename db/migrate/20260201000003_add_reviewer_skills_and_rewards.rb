# frozen_string_literal: true

# Add reviewer skills and review rewards
#
# Humans reviewing AI-generated work need appropriate skills.
# Reviewers earn tokens for quality reviews.
#
# Skills system:
# - Users declare their skills/expertise areas
# - Skills are verified through past contributions
# - Bounty types require specific skills to review
#
# Review rewards:
# - Reviewers earn a percentage of bounty points
# - Quality multiplier based on review history
# - Track review quality metrics
#
class AddReviewerSkillsAndRewards < ActiveRecord::Migration[8.0]
  def change
    # ═══════════════════════════════════════════════════════════════════════════
    # USER SKILLS
    # ═══════════════════════════════════════════════════════════════════════════
    
    create_table :user_skills do |t|
      t.references :user, null: false, foreign_key: true
      t.string :skill_type, null: false  # Maps to bounty_type: bug, feature, documentation, etc.
      t.string :proficiency_level, default: 'beginner'  # beginner, intermediate, expert
      t.boolean :verified, default: false
      t.integer :verified_contributions, default: 0  # Number of approved contributions in this area
      t.integer :reviews_completed, default: 0
      t.decimal :review_accuracy, precision: 5, scale: 2, default: 100.0  # % of reviews upheld
      t.jsonb :endorsements, default: []  # Other users who endorsed this skill
      t.jsonb :metadata, default: {}
      t.timestamps
      
      t.index [:user_id, :skill_type], unique: true
      t.index [:skill_type, :proficiency_level]
      t.index [:verified, :skill_type]
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # REVIEW RECORDS
    # ═══════════════════════════════════════════════════════════════════════════
    
    create_table :bounty_reviews do |t|
      t.references :bounty, null: false, foreign_key: true
      t.references :reviewer, null: false, foreign_key: { to_table: :users }
      t.references :entity, null: false, foreign_key: true
      
      # Review details
      t.string :decision, null: false  # approved, rejected
      t.text :notes
      t.integer :quality_assessment  # 1-5 rating of the work
      t.jsonb :criteria_scores, default: {}  # Detailed scoring: completeness, quality, etc.
      
      # External agent info (if applicable)
      t.references :external_agent_execution, foreign_key: true, null: true
      
      # Reward tracking
      t.decimal :review_points, precision: 10, scale: 2, default: 0
      t.decimal :tokens_earned, precision: 18, scale: 4, default: 0
      t.boolean :reward_processed, default: false
      
      # Quality tracking
      t.boolean :was_overturned, default: false  # If another reviewer/admin overturned
      t.references :overturned_by, foreign_key: { to_table: :users }, null: true
      t.string :overturn_reason
      
      t.timestamps
      
      t.index [:bounty_id, :reviewer_id], unique: true
      t.index [:reviewer_id, :created_at]
      t.index [:decision, :created_at]
      t.index :reward_processed
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # REVIEW POOL CONFIGURATION
    # ═══════════════════════════════════════════════════════════════════════════
    
    # Track eligible reviewers for each bounty type
    create_table :reviewer_eligibility do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.string :bounty_type, null: false  # bug, feature, documentation, etc.
      t.boolean :is_eligible, default: false
      t.string :eligibility_reason  # verified_skill, admin, creator, contribution_history
      t.integer :priority, default: 0  # Higher = preferred reviewer
      t.datetime :last_review_at
      t.integer :active_reviews, default: 0  # Prevent overload
      t.timestamps
      
      t.index [:entity_id, :bounty_type, :is_eligible], name: 'idx_reviewer_eligibility_lookup'
      t.index [:user_id, :entity_id, :bounty_type], unique: true, name: 'idx_reviewer_eligibility_unique'
    end

    # Add review reward percentage to bounties
    add_column :bounties, :review_reward_percentage, :decimal, precision: 5, scale: 2, default: 10.0
    add_column :bounties, :review_reward_points, :decimal, precision: 10, scale: 2
  end
end
