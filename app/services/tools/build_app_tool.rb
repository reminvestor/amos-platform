# frozen_string_literal: true

module Tools
  # BuildAppTool - Builds an app from an approved blueprint
  #
  # This tool creates all the database tables, models, canvases,
  # actions, tools, and the app assistant from the blueprint.
  #
  class BuildAppTool < BaseTool
    # DEPRECATED: Use build_application instead. This tool is a duplicate.
    
    def self.metadata
      {
        name: "build_app",
        description: "DEPRECATED - Use build_application instead. This tool duplicates build_application functionality.",
        category: "deprecated",
        input_schema: {
          type: "object",
          properties: {
            app_id: {
              type: "integer",
              description: "The ID of the app to build"
            },
            confirm: {
              type: "boolean",
              description: "Confirm building (default: true)"
            }
          },
          required: ["app_id"]
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      app_id = get_arg(args, :app_id)
      confirm = get_arg(args, :confirm) != false
      
      if error = validate_required_args(args, [:app_id])
        return error
      end
      
      app = App.find_by(id: app_id, entity_id: entity.id)
      unless app
        return error_response("App not found: #{app_id}")
      end
      
      unless app.planning?
        return error_response("App must be in 'planning' status to build. Current: #{app.status}")
      end
      
      blueprint = app.blueprint
      if blueprint.blank? || blueprint['modules'].blank?
        return error_response("App has no blueprint or modules defined")
      end
      
      # Start the build
      app.start_build!
      
      begin
        build_results = {
          modules: [],
          canvases: [],
          actions: [],
          tools: [],
          workflows: [],
          assistant: nil
        }
        
        # Build each module
        blueprint['modules'].each do |mod_blueprint|
          result = build_module(app, mod_blueprint)
          build_results[:modules] << result[:module]
          build_results[:canvases] += result[:canvases]
          build_results[:actions] += result[:actions]
          build_results[:tools] += result[:tools]
        end
        
        # Build workflows
        (blueprint['workflows'] || []).each do |wf_blueprint|
          workflow = build_workflow(app, wf_blueprint)
          build_results[:workflows] << workflow if workflow
        end
        
        # Build app assistant
        if blueprint['app_assistant'].present?
          assistant = build_assistant(app, blueprint['app_assistant'])
          build_results[:assistant] = assistant
        end
        
        # Complete the build
        app.complete_build!
        
        success_response(
          app_id: app.id,
          app_name: app.name,
          status: app.status,
          build_complete: true,
          results: {
            modules_created: build_results[:modules].length,
            canvases_created: build_results[:canvases].length,
            actions_created: build_results[:actions].length,
            tools_created: build_results[:tools].length,
            workflows_created: build_results[:workflows].length,
            assistant_created: build_results[:assistant].present?
          },
          module_slugs: build_results[:modules].map { |m| m.slug },
          primary_canvas: build_results[:canvases].find { |c| c.is_default }&.slug,
          next_step: 'Show the user their new app in preview mode',
          message: <<~MSG
            🎉 **#{app.name}** has been built successfully!
            
            Created:
            - #{build_results[:modules].length} module(s)
            - #{build_results[:canvases].length} canvas(es)
            - #{build_results[:actions].length} action(s)
            #{"- AI Assistant: #{build_results[:assistant].name}" if build_results[:assistant]}
            
            The app is now in **preview mode**. You can test everything and let me know if you want any changes.
            
            Would you like me to show you the app?
          MSG
        )
      rescue => e
        Rails.logger.error "[BuildApp] Build failed: #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
        
        app.update!(
          status: 'designing',
          metadata: app.metadata.merge(
            build_error: e.message,
            build_failed_at: Time.current.iso8601
          )
        )
        
        error_response("Build failed: #{e.message}")
      end
    end
    
    private
    
    def build_module(app, mod_blueprint)
      name = mod_blueprint['name']
      slug = mod_blueprint['slug'] || name.parameterize.underscore
      
      Rails.logger.info "[BuildApp] Building module: #{name}"
      
      # Create the AppModule
      app_module = AppModule.create!(
        entity: entity,
        app: app,
        created_by: user,
        name: name,
        slug: slug,
        description: mod_blueprint['description'],
        icon: mod_blueprint['icon'] || 'database',
        is_primary: mod_blueprint['is_primary'] || false,
        status: 'generating',
        author_type: 'amos',
        field_config: {
          'fields' => mod_blueprint['fields'],
          'sections' => extract_sections(mod_blueprint['fields'])
        },
        metadata: {
          'schema' => {
            'fields' => mod_blueprint['fields'],
            'module' => {
              'name' => name,
              'icon' => mod_blueprint['icon']
            }
          },
          'blueprint' => mod_blueprint
        }
      )
      
      # Create the database table
      create_module_table(app_module, mod_blueprint['fields'])
      
      # Create canvases
      canvases = []
      (mod_blueprint['canvases'] || []).each do |canvas_blueprint|
        canvas = build_canvas(app_module, canvas_blueprint)
        canvases << canvas if canvas
      end
      
      # Create actions
      actions = []
      (mod_blueprint['actions'] || []).each do |action_blueprint|
        action = build_action(app_module, action_blueprint)
        actions << action if action
      end
      
      # Generate tools
      tools = app_module.generate_tools!
      
      # Activate the module
      app_module.activate!
      
      {
        module: app_module,
        canvases: canvases,
        actions: actions,
        tools: tools
      }
    end
    
    def create_module_table(app_module, fields)
      # Generate table schema
      table_name = app_module.slug.pluralize
      
      schema_columns = [
        { 'name' => 'id', 'type' => 'bigint', 'primary' => true },
        { 'name' => 'entity_id', 'type' => 'bigint', 'null' => false, 'index' => true }
      ]
      
      fields.each do |field|
        next if %w[id entity_id created_at updated_at].include?(field['name'])
        
        schema_columns << {
          'name' => field['name'],
          'type' => map_field_to_db_type(field['type']),
          'null' => !field['required'],
          'default' => field['default']
        }
      end
      
      schema_columns += [
        { 'name' => 'created_at', 'type' => 'datetime', 'null' => false },
        { 'name' => 'updated_at', 'type' => 'datetime', 'null' => false }
      ]
      
      # Create ModuleCode record
      module_code = ModuleCode.create!(
        app_module: app_module,
        entity: entity,
        name: app_module.slug.classify,
        code_type: 'model',
        status: 'deployed',
        schema_definition: {
          'table_name' => table_name,
          'columns' => schema_columns
        },
        fields: fields.map { |f| { 'name' => f['name'], 'type' => f['type'] } },
        associations: [{ 'type' => 'belongs_to', 'model' => 'Entity' }]
      )
      
      # Create the actual table
      Modules::DynamicModelLoader.instance.load_model(module_code)
      
      module_code
    end
    
    def build_canvas(app_module, canvas_blueprint)
      canvas_type = canvas_blueprint['type'] || 'list'
      slug = canvas_blueprint['slug'] || "#{app_module.slug}_#{canvas_type}"
      
      Rails.logger.info "[BuildApp] Building canvas: #{canvas_blueprint['name']}"
      
      ModuleCanvas.create!(
        app_module: app_module,
        entity: entity,
        name: canvas_blueprint['name'],
        slug: slug,
        canvas_type: map_canvas_type(canvas_type),
        is_default: canvas_blueprint['is_default'] || false,
        layout: canvas_blueprint['layout'] || 'default',
        sections: canvas_blueprint['sections'] || [],
        tabs: canvas_blueprint['tabs'] || [],
        columns: canvas_blueprint['columns'] || [],
        filters: canvas_blueprint['filters'] || [],
        sorting: canvas_blueprint['sorting'] || [],
        card_config: canvas_blueprint['card_config'] || {},
        html_content: '', # Will be rendered dynamically
        data_sources: [{ 'type' => 'module_data', 'model' => app_module.slug }],
        metadata: {
          'display_fields' => canvas_blueprint['columns'] || [],
          'icon' => app_module.icon,
          'description' => "#{canvas_blueprint['name']} for #{app_module.name}"
        }
      )
    end
    
    def build_action(app_module, action_blueprint)
      Rails.logger.info "[BuildApp] Building action: #{action_blueprint['name']}"
      
      ModuleAction.create!(
        app_module: app_module,
        entity: entity,
        name: action_blueprint['name'],
        slug: action_blueprint['slug'],
        icon: action_blueprint['icon'] || 'play',
        style: action_blueprint['style'] || 'primary',
        location: action_blueprint['location'] || 'toolbar',
        target_field: action_blueprint['target_field'],
        show_when: action_blueprint['show_when'] || {},
        requires_role: action_blueprint['requires_role'] || {},
        behavior_type: action_blueprint['behavior_type'] || 'update',
        behavior_config: action_blueprint['behavior_config'] || {},
        active: true
      )
    end
    
    def build_workflow(app, wf_blueprint)
      return nil if wf_blueprint.blank?
      
      Rails.logger.info "[BuildApp] Building workflow: #{wf_blueprint['name']}"
      
      trigger = wf_blueprint['trigger'] || {}
      
      case trigger['type']
      when 'scheduled'
        # Create a ScheduledAgentTask
        ScheduledAgentTask.create!(
          entity: entity,
          user: user,
          name: wf_blueprint['name'],
          description: "Auto-generated workflow for #{app.name}",
          task_type: 'custom',
          schedule_type: 'daily', # Simplified for now
          run_at_time: '06:00',
          prompt: "Execute workflow: #{wf_blueprint['name']} - #{wf_blueprint['actions']&.to_json}",
          enabled: true,
          execution_mode: 'tool_only'
        )
      when 'field_change'
        # Store as app metadata for now
        # In production, this would create a proper trigger
        app.update!(
          metadata: app.metadata.merge(
            "workflow_#{wf_blueprint['name'].parameterize.underscore}" => wf_blueprint
          )
        )
        wf_blueprint
      else
        nil
      end
    end
    
    def build_assistant(app, assistant_blueprint)
      Rails.logger.info "[BuildApp] Building assistant: #{assistant_blueprint['name']}"
      
      # Build the tools allowlist from module tools
      tools_allowlist = assistant_blueprint['tools'] || []
      
      # Add common tools
      tools_allowlist += %w[
        load_canvas
        get_data
        create_object
        update_object
        ask_user
      ]
      
      AgentPlugin.create!(
        entity: entity,
        app: app,
        name: assistant_blueprint['name'],
        slug: assistant_blueprint['slug'] || "#{app.slug}_assistant",
        description: "AI assistant for #{app.name}",
        agent_type: 'assistant',
        agent_role: 'app_assistant',
        icon: assistant_blueprint['icon'] || 'bot',
        is_active: true,
        invokable: true,
        system_prompt: build_assistant_prompt(app, assistant_blueprint),
        tool_allowlist: tools_allowlist.uniq,
        persona: assistant_blueprint['persona'],
        capabilities: assistant_blueprint['capabilities'] || [],
        metadata: {
          'app_id' => app.id,
          'generated_at' => Time.current.iso8601
        }
      )
    end
    
    def build_assistant_prompt(app, assistant_blueprint)
      <<~PROMPT
        # #{assistant_blueprint['name']}
        
        You are an AI assistant for the **#{app.name}** application.
        
        #{assistant_blueprint['persona']}
        
        ## Your Capabilities
        
        #{format_capabilities(assistant_blueprint['capabilities'])}
        
        ## Available Tools
        
        You have access to these tools:
        #{assistant_blueprint['tools']&.map { |t| "- #{t}" }&.join("\n")}
        
        ## Guidelines
        
        1. Be helpful and proactive in suggesting improvements
        2. Use the available tools to complete tasks
        3. Ask clarifying questions when needed
        4. Provide clear, actionable responses
        5. Learn from user preferences and adapt
      PROMPT
    end
    
    def format_capabilities(capabilities)
      return '' if capabilities.blank?
      
      capabilities.map do |cap|
        "- **#{cap['name']}**: #{cap['description']}"
      end.join("\n")
    end
    
    def extract_sections(fields)
      return [] if fields.blank?
      
      sections = fields.map { |f| f['section'] }.compact.uniq
      
      sections.map do |section|
        {
          'name' => section,
          'label' => section.titleize,
          'icon' => section_icon(section)
        }
      end
    end
    
    def section_icon(section)
      icons = {
        'content' => 'file-text',
        'scheduling' => 'calendar',
        'workflow' => 'git-branch',
        'metrics' => 'bar-chart',
        'advanced' => 'settings',
        'main' => 'file-text'
      }
      icons[section] || 'file-text'
    end
    
    def map_field_to_db_type(field_type)
      case field_type.to_s.downcase
      when 'string', 'select', 'multi_select', 'user_select'
        'string'
      when 'text', 'rich_text'
        'text'
      when 'integer'
        'integer'
      when 'decimal', 'float'
        'decimal'
      when 'boolean'
        'boolean'
      when 'date'
        'date'
      when 'datetime'
        'datetime'
      when 'json', 'array', 'object', 'media_gallery'
        'jsonb'
      when 'reference'
        'bigint'
      else
        'string'
      end
    end
    
    def map_canvas_type(type)
      case type.to_s.downcase
      when 'list', 'data_grid', 'grid'
        'data_grid'
      when 'form', 'editor'
        'form'
      when 'calendar'
        'calendar'
      when 'kanban', 'board'
        'kanban'
      when 'dashboard'
        'dashboard'
      else
        'data_grid'
      end
    end
  end
end
