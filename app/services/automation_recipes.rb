# frozen_string_literal: true

# AutomationRecipes - Pre-built automation patterns that users can quickly deploy
#
# Each recipe is a template that can be customized and deployed as an AutomationCode.
# Recipes are organized by category and include:
# - Name and description
# - Trigger type and config
# - Code template with placeholders
# - Required inputs for customization
#
class AutomationRecipes
  # ============================================
  # RECIPE DEFINITIONS
  # ============================================

  RECIPES = {
    # Notification Recipes
    notifications: {
      slack_on_status_change: {
        id: 'slack_on_status_change',
        name: 'Slack on Status Change',
        description: 'Send a Slack notification when a record status changes.',
        category: 'Notifications',
        category_color: 'success',
        trigger_type: 'status_changed',
        trigger_config_template: { from: '{{from_status}}', to: '{{to_status}}' },
        required_inputs: [
          { name: 'from_status', label: 'From Status', type: 'string', default: 'draft' },
          { name: 'to_status', label: 'To Status', type: 'string', default: 'published' },
          { name: 'slack_channel', label: 'Slack Channel', type: 'string', default: '#general' }
        ],
        code_template: <<~'RUBY'
          def execute(trigger_data)
            item = record
            
            send_slack_message(
              channel: '{{slack_channel}}',
              message: "📢 *#{item[:name] || item[:title] || 'Item'}* status changed to *{{to_status}}*"
            )
            
            log("Sent Slack notification for status change")
            { success: true, message: 'Notification sent' }
          end
        RUBY
      },

      email_on_create: {
        id: 'email_on_create',
        name: 'Email on Record Create',
        description: 'Send an email notification when a new record is created.',
        category: 'Notifications',
        category_color: 'success',
        trigger_type: 'record_created',
        trigger_config_template: {},
        required_inputs: [
          { name: 'to_email', label: 'Send To Email', type: 'email', default: 'team@company.com' },
          { name: 'subject_template', label: 'Subject', type: 'string', default: 'New {{record_type}} Created' }
        ],
        code_template: <<~'RUBY'
          def execute(trigger_data)
            item = record
            
            send_email(
              to: '{{to_email}}',
              subject: '{{subject_template}}'.gsub('{{record_type}}', item[:type] || 'Record'),
              body: "A new item has been created:\\n\\n" +
                    "Name: #{item[:name] || item[:title]}\\n" +
                    "Created at: #{format_date(now, '%B %d, %Y at %I:%M %p')}"
            )
            
            log("Sent email notification for new record")
            { success: true, message: 'Email sent' }
          end
        RUBY
      },

      notify_role_on_assignment: {
        id: 'notify_role_on_assignment',
        name: 'Notify on Assignment',
        description: 'Notify team members when something is assigned to them.',
        category: 'Notifications',
        category_color: 'success',
        trigger_type: 'field_changed',
        trigger_config_template: { field: 'assigned_to' },
        required_inputs: [],
        code_template: <<~'RUBY'
          def execute(trigger_data)
            item = record
            new_assignee_id = changes.dig('assigned_to', 1)
            
            return { success: true, message: 'No assignee' } if new_assignee_id.blank?
            
            notify_user(
              user_id: new_assignee_id,
              message: "You've been assigned to: #{item[:name] || item[:title]}",
              type: 'info'
            )
            
            log("Notified user #{new_assignee_id} of assignment")
            { success: true, message: 'User notified' }
          end
        RUBY
      }
    },

    # Data Management Recipes
    data: {
      update_timestamp: {
        id: 'update_timestamp',
        name: 'Update Timestamp on Change',
        description: 'Automatically update a timestamp field when specific changes occur.',
        category: 'Data',
        category_color: 'info',
        trigger_type: 'status_changed',
        trigger_config_template: { to: '{{target_status}}' },
        required_inputs: [
          { name: 'target_status', label: 'When Status Changes To', type: 'string', default: 'completed' },
          { name: 'timestamp_field', label: 'Timestamp Field to Update', type: 'string', default: 'completed_at' }
        ],
        code_template: <<~'RUBY'
          def execute(trigger_data)
            update_record(
              record[:id],
              { '{{timestamp_field}}' => now.iso8601 }
            )
            
            log("Updated {{timestamp_field}} for record #{record[:id]}")
            { success: true, message: 'Timestamp updated' }
          end
        RUBY
      },

      cascade_status: {
        id: 'cascade_status',
        name: 'Cascade Status to Related Records',
        description: 'When a parent record status changes, update all child records.',
        category: 'Data',
        category_color: 'info',
        trigger_type: 'status_changed',
        trigger_config_template: { to: '{{parent_status}}' },
        required_inputs: [
          { name: 'parent_status', label: 'Parent Status', type: 'string', default: 'archived' },
          { name: 'child_model', label: 'Child Record Type', type: 'string', default: 'tasks' },
          { name: 'child_status', label: 'Child Status To Set', type: 'string', default: 'archived' }
        ],
        code_template: <<~'RUBY'
          def execute(trigger_data)
            parent_id = record[:id]
            
            # Find related records (assuming parent_id foreign key)
            children = query_records(
              model: '{{child_model}}',
              where: { parent_id: parent_id }
            )
            
            children.each do |child|
              update_record(child[:id], { status: '{{child_status}}' })
            end
            
            log("Updated #{children.size} child records to {{child_status}}")
            { success: true, count: children.size }
          end
        RUBY
      }
    },

    # Integration Recipes
    integrations: {
      webhook_on_event: {
        id: 'webhook_on_event',
        name: 'Webhook on Event',
        description: 'Send data to an external webhook when an event occurs.',
        category: 'Integrations',
        category_color: 'warning',
        trigger_type: 'record_created',
        trigger_config_template: {},
        required_inputs: [
          { name: 'webhook_url', label: 'Webhook URL', type: 'url', default: 'https://api.example.com/webhook' },
          { name: 'include_record', label: 'Include Record Data', type: 'boolean', default: true }
        ],
        code_template: <<~'RUBY'
          def execute(trigger_data)
            payload = {
              event: 'record_created',
              timestamp: now.iso8601,
              record: {{include_record}} ? record : { id: record[:id] }
            }
            
            response = http_post(
              '{{webhook_url}}',
              body: payload,
              headers: { 'Content-Type': 'application/json' }
            )
            
            if response[:success]
              log("Webhook sent successfully")
              { success: true, status: response[:status] }
            else
              log("Webhook failed: #{response[:error]}")
              { success: false, error: response[:error] }
            end
          end
        RUBY
      },

      sync_to_crm: {
        id: 'sync_to_crm',
        name: 'Sync Contact to CRM',
        description: 'When a contact is created or updated, sync to external CRM.',
        category: 'Integrations',
        category_color: 'warning',
        trigger_type: 'record_created',
        trigger_config_template: { model: 'Contact' },
        required_inputs: [
          { name: 'crm_api_url', label: 'CRM API URL', type: 'url', default: 'https://api.hubspot.com/contacts' },
          { name: 'api_key', label: 'API Key (stored securely)', type: 'secret' }
        ],
        code_template: <<~'RUBY'
          def execute(trigger_data)
            contact = record
            
            crm_data = {
              email: contact[:email],
              firstName: contact[:first_name],
              lastName: contact[:last_name],
              company: contact[:company]
            }
            
            response = http_post(
              '{{crm_api_url}}',
              body: crm_data,
              headers: { 
                'Content-Type': 'application/json',
                'Authorization': 'Bearer {{api_key}}'
              }
            )
            
            if response[:success]
              log("Synced contact #{contact[:email]} to CRM")
              { success: true, crm_id: response.dig(:body, 'id') }
            else
              log("CRM sync failed: #{response[:error]}")
              { success: false, error: response[:error] }
            end
          end
        RUBY
      }
    },

    # Workflow Recipes
    workflows: {
      approval_workflow: {
        id: 'approval_workflow',
        name: 'Approval Workflow',
        description: 'Notify approvers when something needs review.',
        category: 'Workflows',
        category_color: 'primary',
        trigger_type: 'status_changed',
        trigger_config_template: { to: 'pending_approval' },
        required_inputs: [
          { name: 'approver_role', label: 'Approver Role', type: 'string', default: 'manager' }
        ],
        code_template: <<~'RUBY'
          def execute(trigger_data)
            item = record
            
            # Notify all users with the approver role
            notify_role(
              role: '{{approver_role}}',
              message: "🔔 Approval needed: #{item[:name] || item[:title]}"
            )
            
            # Also send Slack
            send_slack_message(
              channel: '#approvals',
              message: "📋 *New Approval Request*\\n" +
                       "Item: #{item[:name] || item[:title]}\\n" +
                       "Submitted by: User #{item[:created_by_id]}"
            )
            
            log("Sent approval notifications for #{item[:id]}")
            { success: true, message: 'Approvers notified' }
          end
        RUBY
      },

      sla_reminder: {
        id: 'sla_reminder',
        name: 'SLA Reminder',
        description: 'Send reminder if item is open for too long.',
        category: 'Workflows',
        category_color: 'primary',
        trigger_type: 'schedule',
        trigger_config_template: { schedule: 'hourly' },
        required_inputs: [
          { name: 'hours_threshold', label: 'Hours Before Reminder', type: 'number', default: 24 },
          { name: 'status_to_check', label: 'Status to Check', type: 'string', default: 'open' }
        ],
        code_template: <<~'RUBY'
          def execute(trigger_data)
            threshold = {{hours_threshold}}.hours.ago
            
            # Find items that are open for too long
            overdue_items = query_records(
              where: { 
                status: '{{status_to_check}}',
                created_at: { lt: threshold.iso8601 }
              }
            )
            
            overdue_items.each do |item|
              # Notify the assigned user
              if item[:assigned_to_id].present?
                notify_user(
                  user_id: item[:assigned_to_id],
                  message: "⏰ SLA Warning: #{item[:name] || item[:title]} has been open for over {{hours_threshold}} hours",
                  type: 'warning'
                )
              end
            end
            
            log("Checked SLA: #{overdue_items.size} items overdue")
            { success: true, overdue_count: overdue_items.size }
          end
        RUBY
      }
    },

    # Form Recipes
    forms: {
      process_form_submission: {
        id: 'process_form_submission',
        name: 'Process Form Submission',
        description: 'Handle form submissions and create records.',
        category: 'Forms',
        category_color: 'secondary',
        trigger_type: 'form_submit',
        trigger_config_template: { form_id: '{{form_id}}' },
        required_inputs: [
          { name: 'form_id', label: 'Form ID', type: 'string', default: 'contact_form' },
          { name: 'target_model', label: 'Create Record In', type: 'string', default: 'leads' }
        ],
        code_template: <<~'RUBY'
          def execute(trigger_data)
            form_data = trigger_data[:form_data]
            
            # Create a new record from form data
            new_record = create_record(
              model: '{{target_model}}',
              attributes: {
                name: form_data['name'],
                email: form_data['email'],
                message: form_data['message'],
                source: 'web_form',
                status: 'new'
              }
            )
            
            # Send confirmation email
            if form_data['email'].present?
              send_email(
                to: form_data['email'],
                subject: 'Thanks for reaching out!',
                body: "Hi #{form_data['name']},\\n\\nWe received your message and will get back to you soon."
              )
            end
            
            log("Created {{target_model}} record from form: #{new_record[:id]}")
            { success: true, record_id: new_record[:id] }
          end
        RUBY
      }
    }
  }.freeze

  # ============================================
  # CLASS METHODS
  # ============================================

  class << self
    # Get all recipes as a flat list
    def all
      RECIPES.values.flat_map(&:values)
    end

    # Get recipes by category
    def by_category(category)
      RECIPES[category.to_sym]&.values || []
    end

    # Get a specific recipe by ID
    def find(recipe_id)
      all.find { |r| r[:id] == recipe_id.to_s }
    end

    # Get all categories
    def categories
      RECIPES.keys
    end

    # Apply a recipe with user inputs to create an AutomationCode
    def apply(recipe_id:, entity:, user:, inputs: {}, app_module: nil)
      recipe = find(recipe_id)
      return { success: false, error: 'Recipe not found' } unless recipe

      # Replace placeholders in code template
      code = recipe[:code_template].dup
      trigger_config = recipe[:trigger_config_template].deep_dup

      recipe[:required_inputs].each do |input|
        placeholder = "{{#{input[:name]}}}"
        value = inputs[input[:name].to_s] || inputs[input[:name].to_sym] || input[:default]
        
        code.gsub!(placeholder, value.to_s)
        
        # Also replace in trigger config
        trigger_config.transform_values! do |v|
          v.is_a?(String) ? v.gsub(placeholder, value.to_s) : v
        end
      end

      # Create the automation
      automation = AutomationCode.create!(
        entity: entity,
        created_by: user,
        app_module: app_module,
        name: inputs[:name] || recipe[:name],
        slug: (inputs[:name] || recipe[:name]).parameterize,
        description: recipe[:description],
        trigger_type: recipe[:trigger_type],
        trigger_config: trigger_config,
        code: code,
        status: 'draft'
      )

      { success: true, automation: automation }
    rescue ActiveRecord::RecordInvalid => e
      { success: false, error: e.message }
    end

    # Get recipe suggestions based on module type/archetype
    def suggest_for_module(app_module)
      archetype = app_module.metadata&.dig('archetype')&.to_sym
      
      suggestions = []
      
      # Always suggest status change notifications
      suggestions << find('slack_on_status_change')
      
      # Based on archetype
      case archetype
      when :crm
        suggestions << find('sync_to_crm')
        suggestions << find('notify_role_on_assignment')
        suggestions << find('email_on_create')
      when :project_management, :task_tracker
        suggestions << find('sla_reminder')
        suggestions << find('approval_workflow')
        suggestions << find('notify_role_on_assignment')
      when :content_management
        suggestions << find('approval_workflow')
        suggestions << find('webhook_on_event')
      when :inventory, :product_catalog
        suggestions << find('webhook_on_event')
        suggestions << find('cascade_status')
      when :social_media
        suggestions << find('webhook_on_event')
        suggestions << find('sla_reminder')
      else
        # Generic suggestions
        suggestions << find('email_on_create')
        suggestions << find('webhook_on_event')
      end

      suggestions.compact.uniq { |r| r[:id] }
    end
  end
end

