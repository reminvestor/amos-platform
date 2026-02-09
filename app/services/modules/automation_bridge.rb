# frozen_string_literal: true

module Modules
  # AutomationBridge - Connects module events to automation triggers
  #
  # This service listens for module record lifecycle events and triggers
  # any matching automations. It bridges the gap between:
  # - Dynamic module records (created via DynamicModelLoader)
  # - Deterministic automations (AutomationCode)
  #
  # Usage:
  #   # In your model or callback:
  #   Modules::AutomationBridge.on_record_created(record, user)
  #   Modules::AutomationBridge.on_record_updated(record, changes, user)
  #   Modules::AutomationBridge.on_status_changed(record, from_status, to_status, user)
  #
  class AutomationBridge
    class << self
      # Called when a new record is created in a module
      def on_record_created(record, user = nil)
        return unless record.respond_to?(:entity_id)
        
        entity_id = record.entity_id
        model_name = record.class.name
        
        trigger_data = {
          event: 'record_created',
          record: serialize_record(record),
          model: model_name,
          entity_id: entity_id,
          user_id: user&.id,
          timestamp: Time.current.iso8601
        }
        
        find_and_trigger_automations(
          entity_id: entity_id,
          trigger_type: 'record_created',
          trigger_data: trigger_data,
          match_config: { model: model_name }
        )
      end

      # Called when a record is updated
      def on_record_updated(record, changes, user = nil)
        return unless record.respond_to?(:entity_id)
        return if changes.blank?
        
        entity_id = record.entity_id
        model_name = record.class.name
        
        trigger_data = {
          event: 'record_updated',
          record: serialize_record(record),
          changes: changes,
          model: model_name,
          entity_id: entity_id,
          user_id: user&.id,
          timestamp: Time.current.iso8601
        }
        
        # Trigger record_updated automations
        find_and_trigger_automations(
          entity_id: entity_id,
          trigger_type: 'record_updated',
          trigger_data: trigger_data,
          match_config: { model: model_name }
        )
        
        # Check for specific field changes
        changes.each do |field, (old_value, new_value)|
          trigger_field_changed(record, field, old_value, new_value, user)
        end
      end

      # Called when status field changes
      def on_status_changed(record, from_status, to_status, user = nil)
        return unless record.respond_to?(:entity_id)
        return if from_status == to_status
        
        entity_id = record.entity_id
        model_name = record.class.name
        
        trigger_data = {
          event: 'status_changed',
          record: serialize_record(record),
          from: from_status,
          to: to_status,
          model: model_name,
          entity_id: entity_id,
          user_id: user&.id,
          timestamp: Time.current.iso8601
        }
        
        find_and_trigger_automations(
          entity_id: entity_id,
          trigger_type: 'status_changed',
          trigger_data: trigger_data,
          match_config: { from: from_status, to: to_status }
        )
      end

      # Called when any field changes
      def trigger_field_changed(record, field, old_value, new_value, user = nil)
        return unless record.respond_to?(:entity_id)
        return if old_value == new_value
        
        entity_id = record.entity_id
        model_name = record.class.name
        
        trigger_data = {
          event: 'field_changed',
          record: serialize_record(record),
          field: field,
          old_value: old_value,
          new_value: new_value,
          model: model_name,
          entity_id: entity_id,
          user_id: user&.id,
          timestamp: Time.current.iso8601
        }
        
        find_and_trigger_automations(
          entity_id: entity_id,
          trigger_type: 'field_changed',
          trigger_data: trigger_data,
          match_config: { field: field.to_s }
        )
      end

      # Called on form submission
      def on_form_submit(form_data, entity, user = nil)
        trigger_data = {
          event: 'form_submit',
          form_data: form_data,
          form_id: form_data[:form_id] || form_data['form_id'],
          entity_id: entity.id,
          user_id: user&.id,
          timestamp: Time.current.iso8601
        }
        
        find_and_trigger_automations(
          entity_id: entity.id,
          trigger_type: 'form_submit',
          trigger_data: trigger_data,
          match_config: { form_id: trigger_data[:form_id] }
        )
      end

      # Called for webhook events (including integration events like Stripe, HubSpot, etc.)
      def on_webhook(payload, entity, webhook_path)
        trigger_data = {
          event: 'webhook',
          payload: payload,
          path: webhook_path,
          entity_id: entity.id,
          integration: payload[:integration] || payload["integration"],
          event_type: payload[:event_type] || payload["event_type"],
          timestamp: Time.current.iso8601
        }
        
        find_and_trigger_automations(
          entity_id: entity.id,
          trigger_type: 'webhook',
          trigger_data: trigger_data,
          match_config: { path: webhook_path }
        )
      end

      private

      def find_and_trigger_automations(entity_id:, trigger_type:, trigger_data:, match_config: {})
        automations = AutomationCode
          .where(entity_id: entity_id, trigger_type: trigger_type, status: 'active')
          .to_a
        
        matching = automations.select do |automation|
          matches = automation.matches_trigger?(trigger_data.merge(match_config))
          
          # For webhook triggers, also check integration event_filter matching
          if trigger_type == 'webhook' && !matches
            matches = matches_integration_webhook?(automation, trigger_data)
          end
          
          matches
        end
        
        Rails.logger.info "[AutomationBridge] Found #{matching.size} matching automations for #{trigger_type}"
        
        # Determine trigger source
        trigger_source = trigger_data[:integration].present? ? "integration_#{trigger_data[:integration]}" : 'record'
        
        matching.each do |automation|
          Rails.logger.info "[AutomationBridge] Triggering automation: #{automation.name} (ID: #{automation.id})"
          
          # Run in background job for non-blocking execution
          AutomationTriggerJob.perform_later(automation.id, trigger_data.deep_stringify_keys, { trigger_source: trigger_source })
        end
        
        matching.size
      end

      # Check if a webhook automation matches an integration event
      # Compares the automation's trigger_config event_filter with the incoming event type
      def matches_integration_webhook?(automation, trigger_data)
        config = automation.trigger_config
        return false unless config.is_a?(Hash)
        
        event_filter = config["event_filter"] || config[:event_filter]
        return true if event_filter.blank?  # No filter = match all webhooks
        
        incoming_event = trigger_data[:event_type] || trigger_data["event_type"]
        incoming_path = trigger_data[:path] || trigger_data["path"]
        
        # Match by event_filter against event_type or webhook_path
        event_filter == incoming_event ||
          incoming_path&.include?(event_filter) ||
          incoming_path == config["webhook_path"] || incoming_path == config[:webhook_path]
      end

      def serialize_record(record)
        # Serialize record to a hash, handling various record types
        if record.respond_to?(:as_json)
          record.as_json
        elsif record.respond_to?(:attributes)
          record.attributes
        else
          { id: record.try(:id), class: record.class.name }
        end
      rescue => e
        Rails.logger.error "[AutomationBridge] Failed to serialize record: #{e.message}"
        { id: record.try(:id), class: record.class.name }
      end
    end
  end
end

