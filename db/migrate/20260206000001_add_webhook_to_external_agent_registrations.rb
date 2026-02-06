# frozen_string_literal: true

class AddWebhookToExternalAgentRegistrations < ActiveRecord::Migration[8.0]
  def change
    # Guard: table may not exist if EAP migrations haven't run yet
    return unless table_exists?(:external_agent_registrations)

    add_column :external_agent_registrations, :webhook_url, :string unless column_exists?(:external_agent_registrations, :webhook_url)
    add_column :external_agent_registrations, :webhook_secret, :string unless column_exists?(:external_agent_registrations, :webhook_secret)
    add_column :external_agent_registrations, :webhook_events, :string, array: true, default: [] unless column_exists?(:external_agent_registrations, :webhook_events)
    add_column :external_agent_registrations, :webhook_failures, :integer, default: 0 unless column_exists?(:external_agent_registrations, :webhook_failures)
    add_column :external_agent_registrations, :webhook_last_delivered_at, :datetime unless column_exists?(:external_agent_registrations, :webhook_last_delivered_at)
  end
end
