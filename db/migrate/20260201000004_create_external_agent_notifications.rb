# frozen_string_literal: true

# Create notifications table for external agents
#
# AMOS can recommend bounties to external agents via notifications.
# Agents can poll for these or receive webhooks.
#
class CreateExternalAgentNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :external_agent_notifications do |t|
      t.references :external_agent_registration, null: false, foreign_key: true
      t.string :notification_type, null: false  # bounty_recommendation, trust_upgrade, warning, etc.
      t.string :title, null: false
      t.text :message
      t.jsonb :metadata, default: {}
      t.boolean :read, default: false
      t.boolean :actioned, default: false
      t.string :action_taken  # claimed, dismissed, etc.
      t.datetime :read_at
      t.datetime :actioned_at
      t.timestamps

      t.index [:external_agent_registration_id, :read]
      t.index [:notification_type, :created_at]
    end
  end
end
