# frozen_string_literal: true

module Tools
  # UpdateApplicationPlanTool allows granular updates to an existing application plan.
  # Use this for specific modifications when plan_application's refinements aren't enough.
  #
  class UpdateApplicationPlanTool < BaseTool
    def self.metadata
      {
        name: 'update_application_plan',
        description: 'Make specific updates to an existing application plan. ' \
                     'Use for adding/removing fields, changing module names, updating agent config, etc.',
        category: 'platform_factory',
        input_schema: {
          type: 'object',
          properties: {
            plan_id: {
              type: 'integer',
              description: 'ID of the plan to update (optional - uses active plan if omitted)'
            },
            updates: {
              type: 'object',
              description: 'Specific updates to make',
              properties: {
                # Module updates
                add_field: {
                  type: 'object',
                  description: 'Add a field to a module',
                  properties: {
                    module_index: { type: 'integer', description: 'Module index (default: 0)' },
                    name: { type: 'string' },
                    field_type: { type: 'string' },
                    required: { type: 'boolean' },
                    options: { type: 'array', items: { type: 'string' } }
                  }
                },
                remove_field: {
                  type: 'object',
                  description: 'Remove a field from a module',
                  properties: {
                    module_index: { type: 'integer' },
                    field_name: { type: 'string' }
                  }
                },
                rename_module: {
                  type: 'object',
                  description: 'Rename a module',
                  properties: {
                    module_index: { type: 'integer' },
                    new_name: { type: 'string' }
                  }
                },
                add_module_view: {
                  type: 'object',
                  description: 'Add a view to a module',
                  properties: {
                    module_index: { type: 'integer' },
                    view: { type: 'string', enum: %w[list form detail dashboard calendar kanban] }
                  }
                },
                
                # Agent updates
                update_agent_name: { type: 'string' },
                add_agent_capability: { type: 'string' },
                update_agent_personality: { type: 'string' },
                
                # Integration updates
                add_integration: {
                  type: 'object',
                  properties: {
                    slug: { type: 'string' },
                    purpose: { type: 'string' },
                    is_critical: { type: 'boolean' }
                  }
                },
                remove_integration: { type: 'string', description: 'Integration slug to remove' },
                
                # Workflow updates
                add_workflow: {
                  type: 'object',
                  properties: {
                    name: { type: 'string' },
                    trigger: { type: 'string' },
                    from_status: { type: 'string' },
                    to_status: { type: 'string' },
                    actions: { type: 'array', items: { type: 'string' } }
                  }
                },
                remove_workflow: { type: 'string', description: 'Workflow name to remove' },
                
                # Scheduled task updates
                add_scheduled_task: {
                  type: 'object',
                  properties: {
                    name: { type: 'string' },
                    schedule: { type: 'string' },
                    time: { type: 'string' },
                    action: { type: 'string' }
                  }
                },
                remove_scheduled_task: { type: 'string', description: 'Task name to remove' },
                
                # Website updates
                enable_website: { type: 'boolean' },
                add_website_page: {
                  type: 'object',
                  properties: {
                    name: { type: 'string' },
                    template: { type: 'string' },
                    is_dynamic: { type: 'boolean' }
                  }
                },
                update_website_theme: { type: 'string' },
                
                # Web app updates
                enable_web_app: { type: 'boolean' },
                add_auth_method: { type: 'string', enum: %w[email magic_link google github] },
                enable_registration: { type: 'boolean' }
              }
            }
          },
          required: ['updates']
        }
      }
    end

    def execute(args)
      log_execution(args)
      
      plan = find_plan(args)
      return plan if plan.is_a?(Hash) # Error response
      
      unless plan.editable?
        return { success: false, error: "Plan cannot be edited in '#{plan.status}' state" }
      end
      
      updates = get_arg(args, :updates) || {}
      
      if updates.empty?
        return { success: false, error: "No updates specified" }
      end
      
      # Reset to drafting if pending approval
      plan.update!(status: 'drafting') if plan.pending_approval?
      
      # Apply each update
      changes_made = []
      plan_spec = plan.plan_spec.deep_dup
      
      updates.each do |update_type, update_data|
        result = apply_update(plan_spec, update_type.to_s, update_data)
        changes_made << result if result
      end
      
      # Save updated spec
      plan.update!(plan_spec: plan_spec)
      
      # Re-submit for approval
      plan.submit_for_approval!
      
      # Broadcast updated preview
      broadcast_plan_preview(plan)
      
      {
        success: true,
        message: "Plan updated with #{changes_made.count} changes",
        changes: changes_made,
        plan_id: plan.id,
        summary: plan.component_summary,
        canvas_loaded: true
      }
    end
    
    private
    
    def find_plan(args)
      plan_id = get_arg(args, :plan_id)
      
      if plan_id
        plan = ApplicationPlan.find_by(id: plan_id, entity_id: @entity.id)
        return { success: false, error: "Plan not found" } unless plan
        plan
      else
        plan = ApplicationPlan.active.for_entity(@entity.id).for_user(@user.id).recent.first
        return { success: false, error: "No active plan found" } unless plan
        plan
      end
    end
    
    def apply_update(spec, update_type, data)
      case update_type
      when 'add_field'
        add_field_to_module(spec, data)
      when 'remove_field'
        remove_field_from_module(spec, data)
      when 'rename_module'
        rename_module(spec, data)
      when 'add_module_view'
        add_module_view(spec, data)
      when 'update_agent_name'
        update_agent(spec, 'name', data)
      when 'add_agent_capability'
        add_agent_capability(spec, data)
      when 'update_agent_personality'
        update_agent(spec, 'personality', data)
      when 'add_integration'
        add_integration(spec, data)
      when 'remove_integration'
        remove_integration(spec, data)
      when 'add_workflow'
        add_workflow(spec, data)
      when 'remove_workflow'
        remove_workflow(spec, data)
      when 'add_scheduled_task'
        add_scheduled_task(spec, data)
      when 'remove_scheduled_task'
        remove_scheduled_task(spec, data)
      when 'enable_website'
        enable_website(spec) if data
      when 'add_website_page'
        add_website_page(spec, data)
      when 'update_website_theme'
        update_website_theme(spec, data)
      when 'enable_web_app'
        enable_web_app(spec) if data
      when 'add_auth_method'
        add_auth_method(spec, data)
      when 'enable_registration'
        enable_registration(spec, data)
      else
        nil
      end
    end
    
    # ============================================
    # MODULE UPDATES
    # ============================================
    
    def add_field_to_module(spec, data)
      data = data.with_indifferent_access
      module_index = data[:module_index] || 0
      
      return nil unless spec['modules'] && spec['modules'][module_index]
      
      spec['modules'][module_index]['fields'] ||= []
      spec['modules'][module_index]['fields'] << {
        'name' => data[:name],
        'field_type' => data[:field_type] || 'string',
        'required' => data[:required] || false,
        'options' => data[:options]
      }.compact
      
      "Added field '#{data[:name]}' to module"
    end
    
    def remove_field_from_module(spec, data)
      data = data.with_indifferent_access
      module_index = data[:module_index] || 0
      
      return nil unless spec['modules'] && spec['modules'][module_index]
      
      fields = spec['modules'][module_index]['fields'] || []
      original_count = fields.count
      spec['modules'][module_index]['fields'] = fields.reject { |f| f['name'] == data[:field_name] }
      
      if spec['modules'][module_index]['fields'].count < original_count
        "Removed field '#{data[:field_name]}'"
      end
    end
    
    def rename_module(spec, data)
      data = data.with_indifferent_access
      module_index = data[:module_index] || 0
      
      return nil unless spec['modules'] && spec['modules'][module_index]
      
      old_name = spec['modules'][module_index]['name']
      spec['modules'][module_index]['name'] = data[:new_name]
      spec['modules'][module_index]['slug'] = data[:new_name].parameterize.underscore
      
      "Renamed module from '#{old_name}' to '#{data[:new_name]}'"
    end
    
    def add_module_view(spec, data)
      data = data.with_indifferent_access
      module_index = data[:module_index] || 0
      
      return nil unless spec['modules'] && spec['modules'][module_index]
      
      spec['modules'][module_index]['views'] ||= []
      unless spec['modules'][module_index]['views'].include?(data[:view])
        spec['modules'][module_index]['views'] << data[:view]
        "Added '#{data[:view]}' view to module"
      end
    end
    
    # ============================================
    # AGENT UPDATES
    # ============================================
    
    def update_agent(spec, field, value)
      spec['agent'] ||= {}
      spec['agent'][field] = value
      "Updated agent #{field}"
    end
    
    def add_agent_capability(spec, capability)
      spec['agent'] ||= {}
      spec['agent']['capabilities'] ||= []
      unless spec['agent']['capabilities'].include?(capability)
        spec['agent']['capabilities'] << capability
        "Added agent capability: #{capability}"
      end
    end
    
    # ============================================
    # INTEGRATION UPDATES
    # ============================================
    
    def add_integration(spec, data)
      data = data.with_indifferent_access
      spec['integrations'] ||= []
      
      unless spec['integrations'].any? { |i| i['slug'] == data[:slug] }
        spec['integrations'] << {
          'slug' => data[:slug],
          'purpose' => data[:purpose] || 'sync',
          'is_critical' => data[:is_critical] || false
        }
        "Added integration: #{data[:slug]}"
      end
    end
    
    def remove_integration(spec, slug)
      spec['integrations'] ||= []
      original_count = spec['integrations'].count
      spec['integrations'] = spec['integrations'].reject { |i| i['slug'] == slug }
      
      if spec['integrations'].count < original_count
        "Removed integration: #{slug}"
      end
    end
    
    # ============================================
    # WORKFLOW UPDATES
    # ============================================
    
    def add_workflow(spec, data)
      data = data.with_indifferent_access
      spec['workflows'] ||= []
      
      spec['workflows'] << {
        'name' => data[:name],
        'trigger' => data[:trigger] || 'status_change',
        'from_status' => data[:from_status],
        'to_status' => data[:to_status],
        'actions' => data[:actions] || []
      }.compact
      
      "Added workflow: #{data[:name]}"
    end
    
    def remove_workflow(spec, name)
      spec['workflows'] ||= []
      original_count = spec['workflows'].count
      spec['workflows'] = spec['workflows'].reject { |w| w['name'] == name }
      
      if spec['workflows'].count < original_count
        "Removed workflow: #{name}"
      end
    end
    
    # ============================================
    # SCHEDULED TASK UPDATES
    # ============================================
    
    def add_scheduled_task(spec, data)
      data = data.with_indifferent_access
      spec['scheduled_tasks'] ||= []
      
      spec['scheduled_tasks'] << {
        'name' => data[:name],
        'schedule' => data[:schedule] || 'daily',
        'time' => data[:time] || '09:00',
        'action' => data[:action]
      }.compact
      
      "Added scheduled task: #{data[:name]}"
    end
    
    def remove_scheduled_task(spec, name)
      spec['scheduled_tasks'] ||= []
      original_count = spec['scheduled_tasks'].count
      spec['scheduled_tasks'] = spec['scheduled_tasks'].reject { |t| t['name'] == name }
      
      if spec['scheduled_tasks'].count < original_count
        "Removed scheduled task: #{name}"
      end
    end
    
    # ============================================
    # WEBSITE UPDATES
    # ============================================
    
    def enable_website(spec)
      spec['website'] ||= {
        'pages' => [
          { 'name' => 'Home', 'slug' => 'index', 'template' => 'homepage', 'is_homepage' => true },
          { 'name' => 'About', 'slug' => 'about', 'template' => 'content' }
        ],
        'theme' => 'modern',
        'features' => ['search']
      }
      "Enabled public website"
    end
    
    def add_website_page(spec, data)
      data = data.with_indifferent_access
      spec['website'] ||= { 'pages' => [] }
      spec['website']['pages'] ||= []
      
      spec['website']['pages'] << {
        'name' => data[:name],
        'slug' => data[:name].parameterize,
        'template' => data[:template] || 'content',
        'is_dynamic' => data[:is_dynamic] || false
      }
      
      "Added website page: #{data[:name]}"
    end
    
    def update_website_theme(spec, theme)
      spec['website'] ||= { 'pages' => [] }
      spec['website']['theme'] = theme
      "Updated website theme to: #{theme}"
    end
    
    # ============================================
    # WEB APP UPDATES
    # ============================================
    
    def enable_web_app(spec)
      spec['web_app'] ||= {
        'requires_auth' => true,
        'auth_methods' => ['email'],
        'allow_registration' => true
      }
      spec['requires_auth'] = true
      "Enabled web app with authentication"
    end
    
    def add_auth_method(spec, method)
      spec['web_app'] ||= { 'auth_methods' => [] }
      spec['web_app']['auth_methods'] ||= []
      
      unless spec['web_app']['auth_methods'].include?(method)
        spec['web_app']['auth_methods'] << method
        "Added auth method: #{method}"
      end
    end
    
    def enable_registration(spec, enabled)
      spec['web_app'] ||= {}
      spec['web_app']['allow_registration'] = enabled
      enabled ? "Enabled user registration" : "Disabled user registration"
    end
    
    # ============================================
    # HELPERS
    # ============================================
    
    def broadcast_plan_preview(plan)
      session_id = @context[:session_id] if @context
      return unless session_id
      
      ActionCable.server.broadcast(
        "scout_channel_#{session_id}",
        {
          type: 'canvas_load',
          canvas_type: 'application_plan_preview',
          canvas_title: "Plan: #{plan.name}",
          canvas_data: plan.to_preview
        }
      )
    end
  end
end

