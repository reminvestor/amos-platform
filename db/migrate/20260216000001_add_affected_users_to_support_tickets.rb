# frozen_string_literal: true

class AddAffectedUsersToSupportTickets < ActiveRecord::Migration[8.0]
  def change
    # Track which users reported/are affected by this issue
    add_column :support_tickets, :affected_user_ids, :jsonb, default: []
    add_column :support_tickets, :affected_user_count, :integer, default: 1
    add_column :support_tickets, :content_fingerprint, :string  # For non-error dedup (user reports, feature requests)

    add_index :support_tickets, :content_fingerprint
    add_index :support_tickets, :affected_user_count
  end
end
