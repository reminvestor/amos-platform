# frozen_string_literal: true

module Tools
  # GetPlatformCapabilitiesTool provides information about what the AMOS platform
  # can build and integrate with. Used by the Application Planner to understand
  # available options when designing applications.
  #
  class GetPlatformCapabilitiesTool < BaseTool
    def self.metadata
      {
        name: 'get_platform_capabilities',
        description: 'Get information about what the AMOS platform can build. ' \
                     'Use this to understand available archetypes, integrations, field types, ' \
                     'automation options, and more when planning an application.',
        category: 'platform_factory',
        input_schema: {
          type: 'object',
          properties: {
            category: {
              type: 'string',
              enum: %w[archetypes integrations field_types automations features all],
              description: "What capability info to get: 'archetypes' (app templates), " \
                           "'integrations' (external systems), 'field_types' (data types), " \
                           "'automations' (workflows/tasks), 'features' (website/app features), 'all'"
            },
            archetype: {
              type: 'string',
              description: 'Specific archetype to get details for (e.g., "crm", "knowledge_base")'
            }
          },
          required: []
        }
      }
    end

    def execute(args)
      log_execution(args)
      
      category = get_arg(args, :category) || 'all'
      archetype_key = get_arg(args, :archetype)
      
      if archetype_key.present?
        return get_archetype_details(archetype_key)
      end
      
      case category
      when 'archetypes'
        get_archetypes
      when 'integrations'
        get_integrations
      when 'field_types'
        get_field_types
      when 'automations'
        get_automations
      when 'features'
        get_features
      else
        get_all_capabilities
      end
    end
    
    private
    
    def get_all_capabilities
      {
        success: true,
        capabilities: {
          archetypes: archetype_summary,
          integrations: integration_summary,
          field_types: field_types_list,
          automations: automation_options,
          website_features: website_features,
          web_app_features: web_app_features
        },
        message: "AMOS can build complete applications with data modules, AI agents, " \
                 "integrations, automations, and websites. Use a specific category for more details."
      }
    end
    
    def get_archetypes
      archetypes = Modules::ArchetypeIntelligence::ARCHETYPES.map do |key, data|
        {
          key: key.to_s,
          name: data[:name],
          description: data[:description],
          trigger_words: data[:triggers].first(5),
          suggested_integrations: data[:suggested_integrations]&.map { |i| i[:name] },
          workflow_count: data[:suggested_workflows]&.count || 0,
          scheduled_task_count: data[:suggested_scheduled_tasks]&.count || 0
        }
      end
      
      {
        success: true,
        archetypes: archetypes,
        message: "Available archetypes: #{archetypes.map { |a| a[:name] }.join(', ')}"
      }
    end
    
    def get_archetype_details(key)
      data = Modules::ArchetypeIntelligence::ARCHETYPES[key.to_sym]
      
      return { success: false, error: "Unknown archetype: #{key}" } unless data
      
      {
        success: true,
        archetype: {
          key: key,
          name: data[:name],
          description: data[:description],
          core_fields: data[:core_fields],
          suggested_integrations: data[:suggested_integrations],
          suggested_workflows: data[:suggested_workflows],
          suggested_scheduled_tasks: data[:suggested_scheduled_tasks],
          suggested_hub_hooks: data[:suggested_hub_hooks]
        },
        message: "Full details for #{data[:name]} archetype"
      }
    end
    
    def get_integrations
      # Get available integrations from the database
      integrations = Integration.active.map do |integration|
        {
          slug: integration.slug,
          name: integration.name,
          category: integration.category,
          auth_type: integration.auth_type,
          description: integration.description
        }
      end
      
      # Add known integration categories
      categories = integrations.group_by { |i| i[:category] }.transform_values(&:count)
      
      {
        success: true,
        integrations: integrations,
        categories: categories,
        total: integrations.count,
        message: "#{integrations.count} integrations available across #{categories.keys.count} categories"
      }
    end
    
    def get_field_types
      {
        success: true,
        field_types: [
          { type: 'string', description: 'Short text (names, titles)', ui: 'text input' },
          { type: 'text', description: 'Long text (descriptions, content)', ui: 'textarea' },
          { type: 'integer', description: 'Whole numbers', ui: 'number input' },
          { type: 'decimal', description: 'Numbers with decimals (prices)', ui: 'number input' },
          { type: 'boolean', description: 'Yes/No values', ui: 'checkbox' },
          { type: 'date', description: 'Date only', ui: 'date picker' },
          { type: 'datetime', description: 'Date and time', ui: 'datetime picker' },
          { type: 'select', description: 'Single choice from options', ui: 'dropdown' },
          { type: 'multi_select', description: 'Multiple choices', ui: 'checkbox group' },
          { type: 'reference', description: 'Link to another record', ui: 'autocomplete' },
          { type: 'user_select', description: 'Link to a user', ui: 'user picker' },
          { type: 'email', description: 'Email address', ui: 'email input' },
          { type: 'url', description: 'Web URL', ui: 'url input' },
          { type: 'phone', description: 'Phone number', ui: 'phone input' },
          { type: 'currency', description: 'Money amount', ui: 'currency input' },
          { type: 'file', description: 'File attachment', ui: 'file upload' },
          { type: 'image', description: 'Image attachment', ui: 'image upload' },
          { type: 'json', description: 'Structured data', ui: 'JSON editor' }
        ],
        message: "18 field types available for data modeling"
      }
    end
    
    def get_automations
      {
        success: true,
        workflows: {
          description: 'Event-triggered automations that run when something happens',
          triggers: [
            { trigger: 'status_change', description: 'When a record status changes' },
            { trigger: 'record_created', description: 'When a new record is created' },
            { trigger: 'record_updated', description: 'When a record is modified' },
            { trigger: 'field_changed', description: 'When a specific field changes' },
            { trigger: 'scheduled_datetime', description: 'When a datetime field is reached' }
          ],
          actions: [
            'notify_team', 'send_email', 'create_task', 'update_field',
            'call_webhook', 'run_agent', 'create_record', 'archive_record'
          ]
        },
        scheduled_tasks: {
          description: 'Time-based automations that run on a schedule',
          schedules: [
            { schedule: 'hourly', description: 'Every hour' },
            { schedule: 'daily', description: 'Once per day at specified time' },
            { schedule: 'weekly', description: 'Once per week on specified day' },
            { schedule: 'monthly', description: 'Once per month on specified day' },
            { schedule: 'cron', description: 'Custom cron expression' }
          ],
          task_types: [
            'data_sync', 'report_generation', 'email_management',
            'research_update', 'cleanup', 'custom'
          ]
        },
        webhooks: {
          description: 'External triggers that can start automations',
          features: ['Secure auth tokens', 'IP allowlists', 'Rate limiting', 'Payload validation']
        },
        message: "3 automation types: Workflows (event-triggered), Scheduled Tasks (time-based), Webhooks (external triggers)"
      }
    end
    
    def get_features
      {
        success: true,
        website_features: website_features,
        web_app_features: web_app_features,
        canvas_types: [
          'data_grid', 'form', 'detail', 'dashboard', 'calendar',
          'kanban', 'timeline', 'chart', 'custom'
        ],
        message: "Websites and web apps support a variety of features"
      }
    end
    
    # ============================================
    # SUMMARIES
    # ============================================
    
    def archetype_summary
      Modules::ArchetypeIntelligence::ARCHETYPES.map do |key, data|
        { key: key.to_s, name: data[:name] }
      end
    end
    
    def integration_summary
      Integration.active.group(:category).count.transform_keys(&:to_s)
    rescue
      { 'note' => 'Integration count not available' }
    end
    
    def field_types_list
      %w[string text integer decimal boolean date datetime select multi_select reference user_select email url phone currency file image json]
    end
    
    def automation_options
      {
        workflows: %w[status_change record_created record_updated field_changed],
        scheduled: %w[hourly daily weekly monthly cron],
        webhooks: true
      }
    end
    
    def website_features
      %w[search categories comments analytics social_share contact_form newsletter blog]
    end
    
    def web_app_features
      %w[user_dashboard notifications file_uploads activity_feed export_data api_access multi_tenant]
    end
  end
end
