# frozen_string_literal: true

module Tools
  # AutomationDashboardTool - Load the automation monitoring dashboard or apply recipes
  #
  # This tool provides:
  # - Real-time automation status and execution history
  # - Pre-built automation recipes that users can quickly deploy
  # - Automation creation and management
  #
  class AutomationDashboardTool < BaseTool
    def self.metadata
      {
        name: 'automation_dashboard',
        description: 'Load the automation monitoring dashboard to see all automations, their execution history, ' \
                     'and pre-built automation recipes. Also use this to apply automation recipes.',
        category: 'automation',
        input_schema: {
          type: 'object',
          properties: {
            action: {
              type: 'string',
              enum: %w[view_dashboard apply_recipe list_recipes get_suggestions],
              description: 'Action to perform. view_dashboard shows the monitoring dashboard, ' \
                          'apply_recipe creates an automation from a recipe, ' \
                          'list_recipes shows available recipes, ' \
                          'get_suggestions recommends recipes for a module.'
            },
            recipe_id: {
              type: 'string',
              description: 'For apply_recipe: The ID of the recipe to apply.'
            },
            inputs: {
              type: 'object',
              description: 'For apply_recipe: Input values for the recipe placeholders.'
            },
            module_slug: {
              type: 'string',
              description: 'For get_suggestions or apply_recipe: The module to get suggestions for or attach automation to.'
            },
            category: {
              type: 'string',
              enum: %w[notifications data integrations workflows forms],
              description: 'For list_recipes: Filter recipes by category.'
            },
            show_recipes: {
              type: 'boolean',
              description: 'For view_dashboard: Whether to show recipe suggestions in the dashboard.'
            }
          },
          required: %w[action]
        }
      }
    end

    def execute(args)
      action = args['action']

      case action
      when 'view_dashboard'
        view_dashboard(args)
      when 'apply_recipe'
        apply_recipe(args)
      when 'list_recipes'
        list_recipes(args)
      when 'get_suggestions'
        get_suggestions(args)
      else
        error_response("Unknown action: #{action}")
      end
    end

    private

    def view_dashboard(args)
      # Gather automation stats
      automations = AutomationCode.for_entity(@entity).order(created_at: :desc).limit(50)
      recent_executions = AutomationExecution.for_entity(@entity)
                                             .order(created_at: :desc)
                                             .limit(20)
                                             .includes(:automation_code)

      # Calculate stats
      active_count = automations.active.count
      total_count = automations.count
      
      executions_24h = AutomationExecution.for_entity(@entity)
                                          .where('created_at > ?', 24.hours.ago)
      
      success_count = executions_24h.completed.count
      fail_count = executions_24h.failed.count
      total_executions = success_count + fail_count
      success_rate = total_executions > 0 ? ((success_count.to_f / total_executions) * 100).round(1) : 100
      
      avg_time = executions_24h.completed
                               .where.not(started_at: nil, completed_at: nil)
                               .average('EXTRACT(MILLISECOND FROM (completed_at - started_at))')
                               &.round(0) || 0

      dashboard_data = {
        automations: automations.map do |a|
          {
            id: a.id,
            name: a.name,
            trigger_type: a.trigger_type,
            status: a.status,
            execution_count: a.execution_count,
            success_count: a.success_count,
            error_count: a.error_count
          }
        end,
        recent_executions: recent_executions.map do |e|
          {
            id: e.id,
            automation_name: e.automation_code&.name || 'Unknown',
            status: e.status,
            duration_ms: e.started_at && e.completed_at ? ((e.completed_at - e.started_at) * 1000).round(0) : nil,
            error_message: e.error_message,
            created_at: e.created_at
          }
        end,
        stats: {
          total_automations: total_count,
          active_automations: active_count,
          total_executions_24h: total_executions,
          success_rate: success_rate,
          avg_execution_time_ms: avg_time
        },
        show_recipes: args['show_recipes'] || false,
        recipes: args['show_recipes'] ? AutomationRecipes.all.first(6) : []
      }

      broadcast_canvas_load(type: 'automation_dashboard', data: dashboard_data)

      success_response(
        message: "Loaded automation dashboard. #{active_count} active automations, #{total_executions} executions in the last 24 hours.",
        stats: dashboard_data[:stats]
      )
    end

    def apply_recipe(args)
      recipe_id = args['recipe_id']
      inputs = args['inputs'] || {}
      module_slug = args['module_slug']

      return error_response("Recipe ID is required") if recipe_id.blank?

      # Find the module if provided
      app_module = module_slug.present? ? AppModule.find_by(slug: module_slug, entity: @entity) : nil

      result = AutomationRecipes.apply(
        recipe_id: recipe_id,
        entity: @entity,
        user: @user,
        inputs: inputs,
        app_module: app_module
      )

      if result[:success]
        automation = result[:automation]
        
        # Show the automation in the workflow designer
        broadcast_canvas_load(
          type: 'workflow_designer',
          data: {
            workflow_name: automation.name,
            workflow_id: automation.id,
            nodes: build_workflow_nodes(automation)
          }
        )

        success_response(
          message: "Created automation '#{automation.name}' from recipe. It's currently in draft status - test it and then activate when ready.",
          automation_id: automation.id,
          automation_name: automation.name,
          status: automation.status,
          next_steps: [
            "Test the automation with: test_automation(automation_id: #{automation.id})",
            "Activate it when ready: automation.activate!"
          ]
        )
      else
        error_response(result[:error])
      end
    end

    def list_recipes(args)
      category = args['category']

      recipes = if category.present?
        AutomationRecipes.by_category(category)
      else
        AutomationRecipes.all
      end

      formatted_recipes = recipes.map do |r|
        {
          id: r[:id],
          name: r[:name],
          description: r[:description],
          category: r[:category],
          trigger_type: r[:trigger_type],
          required_inputs: r[:required_inputs].map { |i| "#{i[:name]} (#{i[:type]})" }
        }
      end

      success_response(
        message: "Found #{formatted_recipes.size} automation recipes#{category ? " in #{category}" : ''}.",
        recipes: formatted_recipes,
        categories: AutomationRecipes.categories
      )
    end

    def get_suggestions(args)
      module_slug = args['module_slug']
      
      return error_response("Module slug is required") if module_slug.blank?

      app_module = AppModule.find_by(slug: module_slug, entity: @entity)
      return error_response("Module '#{module_slug}' not found") unless app_module

      suggestions = AutomationRecipes.suggest_for_module(app_module)

      formatted_suggestions = suggestions.map do |r|
        {
          id: r[:id],
          name: r[:name],
          description: r[:description],
          category: r[:category],
          trigger_type: r[:trigger_type],
          why: suggest_reason(app_module, r)
        }
      end

      success_response(
        message: "Found #{formatted_suggestions.size} recommended automations for #{app_module.name}.",
        module_name: app_module.name,
        archetype: app_module.metadata&.dig('archetype'),
        suggestions: formatted_suggestions
      )
    end

    def suggest_reason(app_module, recipe)
      case recipe[:id]
      when 'slack_on_status_change'
        "#{app_module.name} has a status field - get notified on changes"
      when 'sync_to_crm'
        "Sync #{app_module.name} records to your CRM"
      when 'notify_role_on_assignment'
        "Notify team members when assigned to #{app_module.name} items"
      when 'sla_reminder'
        "Track SLA for #{app_module.name} items"
      when 'approval_workflow'
        "Add approval workflow for #{app_module.name}"
      when 'webhook_on_event'
        "Send #{app_module.name} events to external systems"
      when 'email_on_create'
        "Email notifications for new #{app_module.name} records"
      else
        "Recommended for #{app_module.name}"
      end
    end

    def build_workflow_nodes(automation)
      nodes = [{
        id: 'trigger',
        type: 'trigger',
        label: "#{automation.trigger_type.titleize}"
      }]

      code = automation.code || ''
      nodes << { id: 'slack', type: 'notification', label: 'Slack' } if code.include?('send_slack_message')
      nodes << { id: 'email', type: 'notification', label: 'Email' } if code.include?('send_email')
      nodes << { id: 'notify', type: 'notification', label: 'Notify' } if code.include?('notify_')
      nodes << { id: 'http', type: 'integration', label: 'HTTP' } if code.include?('http_')
      nodes << { id: 'update', type: 'action', label: 'Update' } if code.include?('update_record')
      nodes << { id: 'create', type: 'action', label: 'Create' } if code.include?('create_record')
      nodes << { id: 'query', type: 'action', label: 'Query' } if code.include?('query_records')

      nodes
    end
  end
end
