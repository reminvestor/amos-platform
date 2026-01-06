# frozen_string_literal: true

class AddAdminApprovalToSupportTickets < ActiveRecord::Migration[8.0]
  def change
    add_column :support_tickets, :admin_approved, :boolean, default: false
    add_column :support_tickets, :admin_approved_by_id, :bigint
    add_column :support_tickets, :admin_approved_at, :datetime

    add_index :support_tickets, :admin_approved
    add_index :support_tickets, [:category, :admin_approved], name: 'idx_tickets_feature_approval'
  end
end


