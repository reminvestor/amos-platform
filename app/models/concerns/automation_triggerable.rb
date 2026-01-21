# frozen_string_literal: true

# AutomationTriggerable - Concern to add automation trigger callbacks to models
#
# Include this concern in any model that should trigger automations on lifecycle events.
# This is automatically included in dynamically-generated module models.
#
# Usage:
#   class MyModel < ApplicationRecord
#     include AutomationTriggerable
#   end
#
# This adds callbacks that trigger automations on:
# - after_create
# - after_update (with changes tracking)
# - status changes (if model has a 'status' field)
#
module AutomationTriggerable
  extend ActiveSupport::Concern

  included do
    # Store the current user for automation context
    attr_accessor :automation_user

    # Track changes for automation triggers
    after_create :trigger_automation_on_create
    after_update :trigger_automation_on_update
    after_update :trigger_automation_on_status_change, if: :status_changed?
  end

  private

  def trigger_automation_on_create
    return unless should_trigger_automations?

    Modules::AutomationBridge.on_record_created(self, automation_user)
  rescue => e
    Rails.logger.error "[AutomationTriggerable] Failed to trigger on_create: #{e.message}"
  end

  def trigger_automation_on_update
    return unless should_trigger_automations?
    return if saved_changes.blank?

    # Filter out non-relevant changes (timestamps, etc.)
    relevant_changes = saved_changes.except('updated_at', 'created_at')
    return if relevant_changes.blank?

    Modules::AutomationBridge.on_record_updated(self, relevant_changes, automation_user)
  rescue => e
    Rails.logger.error "[AutomationTriggerable] Failed to trigger on_update: #{e.message}"
  end

  def trigger_automation_on_status_change
    return unless should_trigger_automations?
    return unless saved_change_to_status?

    old_status, new_status = saved_change_to_status
    return if old_status == new_status

    Modules::AutomationBridge.on_status_changed(self, old_status, new_status, automation_user)
  rescue => e
    Rails.logger.error "[AutomationTriggerable] Failed to trigger on_status_change: #{e.message}"
  end

  def status_changed?
    respond_to?(:saved_change_to_status?) && saved_change_to_status?
  end

  def should_trigger_automations?
    # Don't trigger if this is happening inside an automation (prevent infinite loops)
    return false if Thread.current[:automation_execution_in_progress]

    # Must have an entity_id
    return false unless respond_to?(:entity_id) && entity_id.present?

    true
  end

  class_methods do
    # Create a record with automation user context
    def create_with_automation(attributes, user: nil)
      record = new(attributes)
      record.automation_user = user
      record.save
      record
    end
  end
end

