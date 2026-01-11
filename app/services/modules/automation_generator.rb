# frozen_string_literal: true

module Modules
  # AutomationGenerator
  #
  # Analyzes a module's schema and generates:
  # 1. Workflow configurations for status fields
  # 2. Default scheduled task templates
  # 3. Webhook suggestions for common patterns
  #
  # This makes modules immediately "alive" with automation capabilities.
  #
  class AutomationGenerator
    attr_reader :app_module, :entity, :user

    def initialize(app_module:, user: nil)
      @app_module = app_module
      @entity = app_module.entity
      @user = user || app_module.created_by
    end

    # Main entry point - analyze module and create automations
    def generate!
      results = {
        workflows: [],
        scheduled_tasks: [],
        webhooks: [],
        suggestions: []
      }

      # Analyze the module's fields
      fields = extract_fields

      # Generate workflows for status/state fields
      status_fields = find_status_fields(fields)
      status_fields.each do |field|
        workflow = generate_status_workflow(field)
        results[:workflows] << workflow if workflow
      end

      # Generate scheduled task suggestions
      results[:scheduled_tasks] = generate_scheduled_task_templates

      # Generate webhook suggestions based on module type
      results[:webhooks] = generate_webhook_suggestions

      # Store the automation config in module metadata
      save_automation_config(results)

      results
    end

    private

    def extract_fields
      # Get fields from module schema
      schema = app_module.metadata.dig('schema') || {}
      fields = schema['fields'] || []
      
      # Also check module_canvases for form metadata
      form_canvas = app_module.module_canvases.find_by(canvas_type: 'form')
      if form_canvas&.metadata&.dig('fields').present?
        fields = form_canvas.metadata['fields']
      end

      fields.map { |f| f.stringify_keys }
    end

    # Find fields that look like status/state fields
    def find_status_fields(fields)
      fields.select do |field|
        field_name = field['name'].to_s.downcase
        field_type = (field['field_type'] || field['type']).to_s.downcase
        
        # Match status-like fields
        is_status_name = field_name.in?(%w[status state stage phase lifecycle progress])
        is_enum_type = field_type.in?(%w[enum select string]) && field['options'].present?
        
        is_status_name || (is_enum_type && field_name.include?('status'))
      end
    end

    # Generate a workflow configuration for a status field
    def generate_status_workflow(field)
      field_name = field['name']
      options = field['options'] || []
      
      return nil if options.length < 2

      # Build workflow states from field options
      states = options.map.with_index do |option, idx|
        {
          name: option.to_s,
          order: idx,
          is_initial: idx == 0,
          is_final: idx == options.length - 1,
          color: state_color(option, idx, options.length),
          allowed_transitions: allowed_transitions(option, options, idx)
        }
      end

      workflow_config = {
        field: field_name,
        name: "#{app_module.name} #{field_name.titleize} Workflow",
        description: "Auto-generated workflow for #{field_name} field transitions",
        states: states,
        triggers: generate_workflow_triggers(field_name, states),
        notifications: generate_workflow_notifications(states)
      }

      # Store in module metadata
      workflow_config
    end

    def state_color(state_name, index, total)
      name = state_name.to_s.downcase
      
      # Common status colors
      case name
      when /draft|new|pending|open/
        'secondary'
      when /active|in.?progress|working|processing/
        'primary'
      when /review|approval|waiting/
        'warning'
      when /complete|done|finished|closed|approved/
        'success'
      when /cancel|reject|fail|error|blocked/
        'danger'
      else
        # Gradient based on position
        position = index.to_f / [total - 1, 1].max
        if position < 0.33
          'secondary'
        elsif position < 0.66
          'primary'
        else
          'success'
        end
      end
    end

    def allowed_transitions(current, all_options, current_idx)
      # By default, allow transitions to next state and to cancel states
      transitions = []
      
      # Next state
      if current_idx < all_options.length - 1
        transitions << all_options[current_idx + 1]
      end
      
      # Allow going back one step
      if current_idx > 0
        transitions << all_options[current_idx - 1]
      end
      
      # Allow skipping to cancel/reject if exists
      cancel_states = all_options.select { |o| o.to_s.downcase.match?(/cancel|reject|fail/) }
      transitions += cancel_states
      
      transitions.uniq
    end

    def generate_workflow_triggers(field_name, states)
      triggers = []
      
      states.each do |state|
        # Add notification trigger for important states
        if state[:name].to_s.downcase.match?(/complete|done|approved|reject|fail/)
          triggers << {
            on: "#{field_name}_changed_to_#{state[:name].parameterize.underscore}",
            action: 'notify_user',
            config: {
              message: "#{app_module.name.singularize} is now #{state[:name]}"
            }
          }
        end
        
        # Add Hub notification for state changes
        triggers << {
          on: "#{field_name}_changed_to_#{state[:name].parameterize.underscore}",
          action: 'hub_activity',
          config: {
            activity_type: 'status_change',
            state: state[:name]
          }
        }
      end
      
      triggers
    end

    def generate_workflow_notifications(states)
      # Determine who to notify for different state changes
      {
        on_complete: ['creator', 'assignee'],
        on_reject: ['creator'],
        on_stuck: ['assignee', 'manager'],  # If in same state for too long
        stuck_threshold_hours: 48
      }
    end

    # Generate suggested scheduled tasks for this module type
    def generate_scheduled_task_templates
      templates = []
      
      # Daily summary for the module
      templates << {
        name: "Daily #{app_module.name} Summary",
        description: "Get a daily summary of your #{app_module.name.downcase} activity",
        task_type: 'report_generation',
        schedule_type: 'daily',
        run_at_time: '09:00',
        prompt: "Generate a brief summary of #{app_module.name} activity from yesterday. Include: total records, any status changes, and items that need attention.",
        suggested: true,
        auto_create: false  # Suggest but don't auto-create
      }
      
      # Weekly review
      templates << {
        name: "Weekly #{app_module.name} Review",
        description: "Weekly analysis of #{app_module.name.downcase} trends",
        task_type: 'report_generation',
        schedule_type: 'weekly',
        run_on_day: 1,  # Monday
        run_at_time: '08:00',
        prompt: "Analyze this week's #{app_module.name} data. Identify trends, highlight any issues, and suggest improvements.",
        suggested: true,
        auto_create: false
      }
      
      # Stale item cleanup reminder
      templates << {
        name: "Stale #{app_module.name.singularize} Alert",
        description: "Alert for items that haven't been updated recently",
        task_type: 'custom',
        schedule_type: 'daily',
        run_at_time: '10:00',
        prompt: "Check for any #{app_module.name.singularize.downcase} records that haven't been updated in 7 days. List them so the user can take action.",
        suggested: true,
        auto_create: false
      }
      
      templates
    end

    # Generate webhook suggestions based on module patterns
    def generate_webhook_suggestions
      suggestions = []
      
      # Inbound webhook for creating records
      suggestions << {
        event_name: 'record_create',
        description: "Create a new #{app_module.name.singularize} via external webhook",
        target_type: 'tool',
        target_tool: "create_#{app_module.slug}",
        suggested: true
      }
      
      # Outbound webhook for status changes
      suggestions << {
        event_name: 'status_change',
        description: "Notify external system when status changes",
        target_type: 'webhook_outbound',
        suggested: true
      }
      
      suggestions
    end

    def save_automation_config(config)
      app_module.metadata['automation_config'] = {
        generated_at: Time.current.iso8601,
        workflows: config[:workflows],
        scheduled_task_templates: config[:scheduled_tasks],
        webhook_suggestions: config[:webhooks]
      }
      app_module.save!
    end
  end
end

