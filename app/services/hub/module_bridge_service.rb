# frozen_string_literal: true

module Hub
  # ModuleBridgeService
  #
  # Bridges module activities to the Hub:
  # - Record creation → Hub activity notification
  # - Status changes → Hub status update message
  # - User assignments → Hub participant updates
  # - Module sharing → Hub channel creation
  #
  # This makes modules "social" - activities appear in team feeds.
  #
  class ModuleBridgeService
    attr_reader :entity, :app_module

    def initialize(app_module:)
      @app_module = app_module
      @entity = app_module.entity
    end

    # ============================================
    # MODULE LIFECYCLE EVENTS
    # ============================================

    # Called when a new module is created and shared with team
    def on_module_shared(shared_by:)
      return unless app_module.entity_visible?

      # Find or create a channel for module activities
      channel = find_or_create_module_channel

      # Post announcement to channel
      if channel
        channel.add_system_message(
          content: "📦 **#{shared_by.full_name}** shared a new app: **#{app_module.name}**\n\n#{app_module.description}",
          metadata: {
            event: 'module_shared',
            module_id: app_module.id,
            module_slug: app_module.slug,
            shared_by_id: shared_by.id
          }
        )
      end

      # Notify entity users
      notify_entity_users(
        title: "New app available: #{app_module.name}",
        message: "#{shared_by.full_name} shared a new app with your team",
        action_url: "/scout?canvas=module_#{app_module.slug}_list"
      )
    end

    # ============================================
    # RECORD EVENTS
    # ============================================

    # Called when a record is created in the module
    def on_record_created(record:, created_by:)
      return unless should_notify_hub?

      thread = find_or_create_module_activity_thread

      message_content = build_record_created_message(record, created_by)
      
      thread&.add_message(
        sender: created_by,
        content: message_content,
        message_type: HubMessage::STATUS_UPDATE,
        metadata: {
          event: 'record_created',
          module_id: app_module.id,
          record_id: record.id,
          record_type: app_module.slug.classify
        }
      )
    end

    # Called when a record's status changes
    def on_status_changed(record:, changed_by:, field:, old_value:, new_value:)
      return unless should_notify_hub?

      thread = find_or_create_module_activity_thread

      message_content = "📊 Status changed: **#{record_display_name(record)}**\n" \
                        "#{old_value} → **#{new_value}**"

      thread&.add_message(
        sender: changed_by,
        content: message_content,
        message_type: HubMessage::STATUS_UPDATE,
        metadata: {
          event: 'status_changed',
          module_id: app_module.id,
          record_id: record.id,
          field: field,
          old_value: old_value,
          new_value: new_value
        }
      )

      # Check for workflow triggers
      check_workflow_triggers(record, field, new_value, changed_by)
    end

    # Called when a record is assigned to a user
    def on_record_assigned(record:, assigned_by:, assigned_to:)
      return unless should_notify_hub?

      # Create a DM thread between assigner and assignee about this record
      thread = find_or_create_assignment_thread(assigned_by, assigned_to, record)

      message_content = "📋 You've been assigned: **#{record_display_name(record)}**\n\n" \
                        "Module: #{app_module.name}"

      thread&.add_message(
        sender: assigned_by,
        content: message_content,
        message_type: HubMessage::TEXT,
        metadata: {
          event: 'record_assigned',
          module_id: app_module.id,
          record_id: record.id
        }
      )
    end

    # ============================================
    # WORKFLOW TRIGGERS
    # ============================================

    def check_workflow_triggers(record, field, new_value, changed_by)
      automation_config = app_module.metadata['automation_config']
      return unless automation_config

      workflows = automation_config['workflows'] || []
      
      workflows.each do |workflow|
        next unless workflow['field'] == field
        
        workflow['triggers']&.each do |trigger|
          trigger_event = "#{field}_changed_to_#{new_value.to_s.parameterize.underscore}"
          
          if trigger['on'] == trigger_event
            execute_trigger(trigger, record, changed_by)
          end
        end
      end
    end

    def execute_trigger(trigger, record, user)
      case trigger['action']
      when 'notify_user'
        notify_user_of_trigger(trigger, record, user)
      when 'hub_activity'
        post_hub_activity(trigger, record, user)
      when 'call_agent'
        queue_agent_task(trigger, record, user)
      end
    end

    private

    def should_notify_hub?
      # Only notify for entity-visible modules
      app_module.entity_visible? || app_module.public?
    end

    def find_or_create_module_channel
      TeamChannel.find_or_create_by!(entity: entity, name: 'Apps & Automations') do |channel|
        channel.description = 'Activity from your installed apps'
        channel.is_default = false
        channel.channel_type = 'integration'
      end
    end

    def find_or_create_module_activity_thread
      # Find or create a work_stream thread for this module's activities
      existing = HubThread.where(
        entity: entity,
        thread_type: HubThread::WORK_STREAM
      ).where("metadata->>'module_id' = ?", app_module.id.to_s).first

      return existing if existing

      # Create new thread
      thread = HubThread.create!(
        entity: entity,
        thread_type: HubThread::WORK_STREAM,
        status: 'active',
        subject: "#{app_module.name} Activity",
        started_by: app_module.created_by || entity.entity_users.first&.user,
        metadata: {
          module_id: app_module.id,
          module_slug: app_module.slug,
          module_name: app_module.name
        }
      )

      # Add module creator as participant
      if app_module.created_by
        thread.hub_participants.create!(
          participant: app_module.created_by,
          role: 'owner',
          notify_on_message: true
        )
      end

      thread
    end

    def find_or_create_assignment_thread(assigned_by, assigned_to, record)
      # Create a DM thread for this assignment
      HubThread.create!(
        entity: entity,
        thread_type: HubThread::DM,
        status: 'active',
        subject: "Assignment: #{record_display_name(record)}",
        started_by: assigned_by,
        metadata: {
          module_id: app_module.id,
          record_id: record.id,
          assignment: true
        }
      ).tap do |thread|
        thread.hub_participants.create!(participant: assigned_by, role: 'member')
        thread.hub_participants.create!(participant: assigned_to, role: 'member', notify_on_message: true)
      end
    end

    def build_record_created_message(record, created_by)
      record_name = record_display_name(record)
      "➕ New #{app_module.name.singularize}: **#{record_name}**"
    end

    def record_display_name(record)
      # Try common name fields
      %w[name title subject label description].each do |field|
        value = record.try(field)
        return value.to_s.truncate(50) if value.present?
      end
      
      "#{app_module.name.singularize} ##{record.id}"
    end

    def notify_entity_users(title:, message:, action_url: nil)
      # Use existing notification system
      entity.entity_users.each do |eu|
        next unless eu.user
        
        # This would integrate with your notification system
        # For now, just log
        Rails.logger.info "[ModuleBridge] Would notify #{eu.user.email}: #{title}"
      end
    end

    def notify_user_of_trigger(trigger, record, user)
      config = trigger['config'] || {}
      message = config['message'] || "#{app_module.name} status changed"
      
      Rails.logger.info "[ModuleBridge] Trigger notification: #{message} for user #{user.id}"
      
      # Create a notification (integrate with your notification system)
    end

    def post_hub_activity(trigger, record, user)
      thread = find_or_create_module_activity_thread
      config = trigger['config'] || {}
      
      thread&.add_message(
        sender: user,
        content: "🔔 #{record_display_name(record)}: #{config['state'] || 'Updated'}",
        message_type: HubMessage::STATUS_UPDATE
      )
    end

    def queue_agent_task(trigger, record, user)
      config = trigger['config'] || {}
      agent_slug = config['agent'] || 'scout'
      
      # Queue an agent task for this trigger
      Rails.logger.info "[ModuleBridge] Would queue agent task: #{agent_slug} for record #{record.id}"
    end
  end
end

