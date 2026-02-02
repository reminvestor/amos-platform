# frozen_string_literal: true

# Add human review requirements and user-funded bounty support
#
# Human Review:
# - All bounty completions now require human verification
# - System bounties (created by AMOS) require platform admin review
# - User-created bounties are reviewed by the creator
# - External agent work goes through AI pre-review, then human final approval
#
# User-Funded Bounties:
# - Users can create bounties and fund them from their AMOS token balance
# - Tokens are escrowed when bounty is created
# - Released to claimant when approved, or refunded if cancelled
#
class AddHumanReviewAndUserFundingToBounties < ActiveRecord::Migration[8.0]
  def change
    # Human review requirements
    add_column :bounties, :requires_human_review, :boolean, default: true, null: false
    add_column :bounties, :requires_pr, :boolean, default: false, null: false
    add_column :bounties, :ai_review_completed, :boolean, default: false
    add_column :bounties, :ai_review_result, :jsonb, default: {}
    add_column :bounties, :ai_review_at, :datetime
    add_column :bounties, :human_review_at, :datetime
    add_column :bounties, :human_review_notes, :text
    
    # User-funded bounty support
    add_column :bounties, :funding_source, :string, default: 'platform', null: false
    add_reference :bounties, :funded_by, foreign_key: { to_table: :users }, null: true
    add_column :bounties, :funded_amount, :decimal, precision: 18, scale: 4, default: 0
    add_column :bounties, :escrow_status, :string, default: 'none'  # none, escrowed, released, refunded
    add_column :bounties, :escrow_transaction_id, :string
    
    # GitHub/PR requirements for code bounties
    add_column :bounties, :target_repo, :string  # e.g., 'org/repo'
    add_column :bounties, :target_branch, :string, default: 'main'
    add_column :bounties, :pr_template, :text  # Template for PR description
    
    # Track who can review (for user-funded bounties)
    add_column :bounties, :reviewer_type, :string, default: 'auto'  # auto, creator, admin, specific_user
    add_reference :bounties, :designated_reviewer, foreign_key: { to_table: :users }, null: true

    # Add indexes
    add_index :bounties, :funding_source
    add_index :bounties, :escrow_status
    add_index :bounties, :requires_pr
    add_index :bounties, [:funded_by_id, :status]

    # Update external_agent_executions to track human review status
    add_column :external_agent_executions, :ai_pre_review_passed, :boolean, default: false
    add_column :external_agent_executions, :awaiting_human_review, :boolean, default: false
    add_column :external_agent_executions, :human_reviewer_id, :bigint
    add_column :external_agent_executions, :human_review_at, :datetime
    add_column :external_agent_executions, :human_review_notes, :text

    add_index :external_agent_executions, :awaiting_human_review
    add_foreign_key :external_agent_executions, :users, column: :human_reviewer_id
  end
end
