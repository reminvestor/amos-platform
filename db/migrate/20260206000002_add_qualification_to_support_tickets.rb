# frozen_string_literal: true

# Add ticket qualification fields for bounty readiness
#
# These fields enable AI-assessed quality scoring before a ticket
# becomes a bounty. Better tickets = better bounties = better work.
#
class AddQualificationToSupportTickets < ActiveRecord::Migration[8.0]
  def change
    return unless table_exists?(:support_tickets)

    # Readiness scoring
    add_column :support_tickets, :readiness_score, :integer, default: 0 unless column_exists?(:support_tickets, :readiness_score)
    add_column :support_tickets, :readiness_assessed_at, :datetime unless column_exists?(:support_tickets, :readiness_assessed_at)
    add_column :support_tickets, :readiness_notes, :text unless column_exists?(:support_tickets, :readiness_notes)

    # Structured fields for actionable tickets
    add_column :support_tickets, :steps_to_reproduce, :text unless column_exists?(:support_tickets, :steps_to_reproduce)
    add_column :support_tickets, :expected_behavior, :text unless column_exists?(:support_tickets, :expected_behavior)
    add_column :support_tickets, :actual_behavior, :text unless column_exists?(:support_tickets, :actual_behavior)
    add_column :support_tickets, :acceptance_criteria, :jsonb, default: [] unless column_exists?(:support_tickets, :acceptance_criteria)
    add_column :support_tickets, :affected_component, :string unless column_exists?(:support_tickets, :affected_component)
    add_column :support_tickets, :affected_url, :string unless column_exists?(:support_tickets, :affected_url)
    add_column :support_tickets, :environment_info, :jsonb, default: {} unless column_exists?(:support_tickets, :environment_info)

    # Scope and effort estimation
    add_column :support_tickets, :scope_summary, :text unless column_exists?(:support_tickets, :scope_summary)
    add_column :support_tickets, :estimated_effort, :string unless column_exists?(:support_tickets, :estimated_effort)
    add_column :support_tickets, :suggested_approach, :text unless column_exists?(:support_tickets, :suggested_approach)

    # Feature request fields
    add_column :support_tickets, :user_story, :text unless column_exists?(:support_tickets, :user_story)
    add_column :support_tickets, :business_value, :text unless column_exists?(:support_tickets, :business_value)

    # Bounty linkage
    add_column :support_tickets, :bounty_eligible, :boolean, default: false unless column_exists?(:support_tickets, :bounty_eligible)
    add_column :support_tickets, :bounty_blocked_reason, :string unless column_exists?(:support_tickets, :bounty_blocked_reason)

    add_index :support_tickets, :readiness_score unless index_exists?(:support_tickets, :readiness_score)
    add_index :support_tickets, :bounty_eligible unless index_exists?(:support_tickets, :bounty_eligible)
  end
end
