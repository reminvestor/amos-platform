# frozen_string_literal: true

# WorkflowTriggerable - Concern for models that can trigger workflows
#
# Include this in any model that should be able to trigger automated workflows.
# Examples: LandingPage (form submissions), AppModule (record events), WebsitePage (visits)
#
# Usage:
#   class LandingPage < ApplicationRecord
#     include WorkflowTriggerable
#   end
#
# Then you can:
#   landing_page.workflow_triggers  # Get all workflow triggers for this model
#   landing_page.fire_workflow!(event_type, context)  # Fire matching workflows
#
module WorkflowTriggerable
  extend ActiveSupport::Concern

  included do
    # Polymorphic association - this model can be the source of workflow triggers
    has_many :workflow_triggers, as: :triggerable, dependent: :destroy
  end

  # Fire all matching workflow triggers for this model
  #
  # @param event_type [Symbol] The type of event (:form, :webhook, :record_created, etc.)
  # @param context [Hash] The context data to pass to the workflow
  # @return [Array<Hash>] Results from each triggered workflow
  def fire_workflows!(event_type, context = {})
    triggers = workflow_triggers.active.by_type(event_type.to_s)
    
    results = []
    
    triggers.each do |trigger|
      result = trigger.fire!(context.merge(
        triggerable_type: self.class.name,
        triggerable_id: id,
        triggerable_name: respond_to?(:name) ? name : (respond_to?(:title) ? title : nil)
      ))
      
      results << {
        trigger_id: trigger.id,
        workflow_name: trigger.automation_code.name,
        success: result[:success],
        execution_id: result[:execution_id],
        error: result[:error]
      }
    end

    results
  end

  # Fire workflows for a specific event with additional filtering
  def fire_matching_workflows!(event_type, event_data = {})
    triggers = workflow_triggers.active.by_type(event_type.to_s)
    
    results = []
    
    triggers.each do |trigger|
      # Check if trigger matches the event data (for record events with conditions)
      next unless trigger_matches?(trigger, event_data)
      
      result = trigger.fire!(event_data.merge(
        triggerable_type: self.class.name,
        triggerable_id: id
      ))
      
      results << {
        trigger_id: trigger.id,
        workflow_name: trigger.automation_code.name,
        result: result
      }
    end

    results
  end

  # Get active workflows that can be triggered by this model
  def available_workflows
    workflow_triggers.active.includes(:automation_code).map do |trigger|
      {
        trigger_id: trigger.id,
        trigger_type: trigger.trigger_type,
        workflow_id: trigger.automation_code_id,
        workflow_name: trigger.automation_code.name,
        workflow_status: trigger.automation_code.status,
        is_compiled: trigger.automation_code.is_compiled?
      }
    end
  end

  # Create a new workflow trigger for this model
  #
  # @param automation_code [AutomationCode] The workflow to trigger
  # @param trigger_type [String] The trigger type (form, webhook, etc.)
  # @param config [Hash] Additional trigger configuration
  # @return [WorkflowTrigger] The created trigger
  def add_workflow_trigger(automation_code, trigger_type:, config: {})
    workflow_triggers.create!(
      entity: respond_to?(:entity) ? entity : automation_code.entity,
      automation_code: automation_code,
      trigger_type: trigger_type,
      trigger_config: config,
      status: 'active',
      enabled: true
    )
  end

  private

  def trigger_matches?(trigger, event_data)
    case trigger.trigger_type
    when 'field_changed'
      field = trigger.trigger_config['field']
      return false unless field
      
      changes = event_data[:changes] || event_data['changes'] || {}
      changes.key?(field) || changes.key?(field.to_sym)
      
    when 'status_changed'
      from = trigger.trigger_config['from']
      to = trigger.trigger_config['to']
      
      changes = event_data[:changes] || event_data['changes'] || {}
      status_change = changes['status'] || changes[:status]
      
      return false unless status_change
      
      old_val, new_val = status_change
      (from.blank? || from == old_val) && (to.blank? || to == new_val)
      
    else
      true  # No additional matching needed
    end
  end
end
