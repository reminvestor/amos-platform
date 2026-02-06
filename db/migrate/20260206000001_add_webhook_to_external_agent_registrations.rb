# frozen_string_literal: true

class AddWebhookToExternalAgentRegistrations < ActiveRecord::Migration[8.0]
  def change
    add_column :external_agent_registrations, :webhook_url, :string
    add_column :external_agent_registrations, :webhook_secret, :string
    add_column :external_agent_registrations, :webhook_events, :string, array: true, default: []
    add_column :external_agent_registrations, :webhook_failures, :integer, default: 0
    add_column :external_agent_registrations, :webhook_last_delivered_at, :datetime
  end
end
