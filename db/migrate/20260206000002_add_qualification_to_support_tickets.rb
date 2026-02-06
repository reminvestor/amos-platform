# frozen_string_literal: true

# Add ticket qualification fields for bounty readiness
#
# These fields enable AI-assessed quality scoring before a ticket
# becomes a bounty. Better tickets = better bounties = better work.
#
class AddQualificationToSupportTickets < ActiveRecord::Migration[8.0]
  def change
    # Readiness scoring
    add_column :support_tickets, :readiness_score, :integer, default: 0
    add_column :support_tickets, :readiness_assessed_at, :datetime
    add_column :support_tickets, :readiness_notes, :text

    # Structured fields for actionable tickets
    add_column :support_tickets, :steps_to_reproduce, :text
    add_column :support_tickets, :expected_behavior, :text
    add_column :support_tickets, :actual_behavior, :text
    add_column :support_tickets, :acceptance_criteria, :jsonb, default: []
    add_column :support_tickets, :affected_component, :string
    add_column :support_tickets, :affected_url, :string
    add_column :support_tickets, :environment_info, :jsonb, default: {}

    # Scope and effort estimation
    add_column :support_tickets, :scope_summary, :text
    add_column :support_tickets, :estimated_effort, :string  # 'trivial', 'small', 'medium', 'large', 'epic'
    add_column :support_tickets, :suggested_approach, :text

    # Feature request fields
    add_column :support_tickets, :user_story, :text
    add_column :support_tickets, :business_value, :text

    # Bounty linkage
    add_column :support_tickets, :bounty_eligible, :boolean, default: false
    add_column :support_tickets, :bounty_blocked_reason, :string

    add_index :support_tickets, :readiness_score
    add_index :support_tickets, :bounty_eligible
  end
end
