# frozen_string_literal: true

module Tools
  # GenerateAppBlueprintTool - Creates a comprehensive app blueprint from discovery
  #
  # After the discovery conversation, this tool generates a full blueprint
  # including modules, fields, canvases, actions, workflows, and app assistant.
  #
  class GenerateAppBlueprintTool < BaseTool
    def self.metadata
      {
        name: "generate_app_blueprint",
        description: "Generate a complete app blueprint based on discovery answers. Creates module definitions, field configurations, UI layouts, actions, and workflows.",
        category: "app_building",
        input_schema: {
          type: "object",
          properties: {
            app_id: { type: "integer", description: "The ID of the app to generate blueprint for" },
            discovery_answers: { type: "object", description: "Answers from the discovery conversation" },
            modules: { 
              type: "array", 
              items: { type: "object" },
              description: "Array of module definitions with names and descriptions" 
            },
            workflows: { 
              type: "array", 
              items: { type: "object" },
              description: "Array of workflow definitions" 
            },
            include_assistant: { type: "boolean", description: "Whether to include an AI assistant for this app" }
          },
          required: ["app_id", "modules"]
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      app_id = get_arg(args, :app_id)
      discovery_answers = get_arg(args, :discovery_answers) || {}
      modules_def = get_arg(args, :modules) || []
      workflows_def = get_arg(args, :workflows) || []
      include_assistant = get_arg(args, :include_assistant) != false
      
      if error = validate_required_args(args, [:app_id, :modules])
        return error
      end
      
      app = App.find_by(id: app_id, entity_id: entity.id)
      unless app
        return error_response("App not found: #{app_id}")
      end
      
      unless app.designing? || app.planning?
        return error_response("App is not in design phase. Current status: #{app.status}")
      end
      
      # Generate the full blueprint
      blueprint = generate_blueprint(app, discovery_answers, modules_def, workflows_def, include_assistant)
      
      # Update the app with the blueprint
      app.update!(
        blueprint: blueprint,
        status: 'planning',
        intent: app.intent.merge(
          discovery_answers: discovery_answers,
          discovery_completed_at: Time.current.iso8601
        ),
        metadata: app.metadata.merge(
          design_phase: 'blueprint_review'
        )
      )
      
      # Generate summary for user review
      summary = generate_blueprint_summary(blueprint)
      
      success_response(
        app_id: app.id,
        status: 'planning',
        blueprint_generated: true,
        modules_count: blueprint['modules']&.length || 0,
        workflows_count: blueprint['workflows']&.length || 0,
        has_assistant: blueprint['app_assistant'].present?,
        summary: summary,
        next_step: 'Show the blueprint to the user for review and approval',
        message: <<~MSG
          I've created a blueprint for your **#{app.name}** app!
          
          #{summary}
          
          Would you like to:
          - **Review the details** of any module or workflow
          - **Make changes** before building
          - **Approve and build** the app
        MSG
      )
    rescue ActiveRecord::RecordNotFound => e
      error_response("App not found: #{app_id}")
    rescue => e
      Rails.logger.error "[GenerateAppBlueprint] Error: #{e.message}"
      error_response("Failed to generate blueprint: #{e.message}")
    end
    
    private
    
    def generate_blueprint(app, answers, modules_def, workflows_def, include_assistant)
      blueprint = {
        'app' => {
          'name' => app.name,
          'slug' => app.slug,
          'description' => app.description,
          'icon' => suggest_icon(app.name, app.description),
          'color' => suggest_color(modules_def.first&.dig('name'))
        },
        'modules' => [],
        'workflows' => [],
        'integrations' => []
      }
      
      # Generate modules
      modules_def.each_with_index do |mod_def, index|
        blueprint['modules'] << generate_module_blueprint(
          mod_def, 
          answers, 
          is_primary: index == 0
        )
      end
      
      # Generate workflows
      workflows_def.each do |wf_def|
        blueprint['workflows'] << generate_workflow_blueprint(wf_def, answers)
      end
      
      # Add standard workflows based on answers
      if has_approval_workflow?(answers)
        blueprint['workflows'] << generate_approval_workflow(modules_def.first)
      end
      
      if has_scheduling?(answers)
        blueprint['workflows'] << generate_scheduling_workflow(modules_def.first)
      end
      
      # Generate app assistant if requested
      if include_assistant
        blueprint['app_assistant'] = generate_assistant_blueprint(app, modules_def, answers)
      end
      
      # Add integrations based on answers
      if answers['integrations'].present?
        blueprint['integrations'] = parse_integrations(answers['integrations'])
      end
      
      blueprint
    end
    
    def generate_module_blueprint(mod_def, answers, is_primary: false)
      name = mod_def['name'] || mod_def[:name]
      description = mod_def['description'] || mod_def[:description]
      
      # Generate fields based on module type and answers
      fields = generate_fields_for_module(name, description, answers)
      
      {
        'name' => name,
        'slug' => name.parameterize.underscore,
        'description' => description,
        'is_primary' => is_primary,
        'icon' => suggest_icon(name, description),
        'fields' => fields,
        'canvases' => generate_canvases_for_module(name, fields, answers),
        'actions' => generate_actions_for_module(name, fields, answers),
        'tools' => generate_tools_for_module(name)
      }
    end
    
    def generate_fields_for_module(name, description, answers)
      fields = []
      singular = name.singularize
      
      # Core fields every module needs
      fields << {
        'name' => 'title',
        'type' => 'string',
        'label' => "#{singular} Title",
        'required' => true,
        'section' => 'content',
        'order' => 1
      }
      
      # Content field for content-heavy modules
      if is_content_module?(name, description)
        fields << {
          'name' => 'content',
          'type' => 'text',
          'label' => 'Content',
          'required' => true,
          'section' => 'content',
          'order' => 2,
          'ui_component' => 'rich_text_editor',
          'ai_assist' => true
        }
      else
        fields << {
          'name' => 'description',
          'type' => 'text',
          'label' => 'Description',
          'required' => false,
          'section' => 'content',
          'order' => 2
        }
      end
      
      # Status field
      status_options = ['draft']
      if has_approval_workflow?(answers)
        status_options += ['pending_review', 'approved', 'rejected']
      end
      if has_scheduling?(answers)
        status_options += ['scheduled', 'published']
      end
      status_options << 'archived'
      
      fields << {
        'name' => 'status',
        'type' => 'select',
        'label' => 'Status',
        'required' => true,
        'section' => 'workflow',
        'order' => 1,
        'options' => status_options.uniq,
        'default' => 'draft'
      }
      
      # Scheduling fields
      if has_scheduling?(answers)
        fields << {
          'name' => 'scheduled_for',
          'type' => 'datetime',
          'label' => 'Scheduled For',
          'section' => 'scheduling',
          'order' => 1,
          'show_when' => { 'field' => 'status', 'in' => ['scheduled', 'approved'] }
        }
      end
      
      # Team assignment
      if has_team_features?(answers)
        fields << {
          'name' => 'assigned_to',
          'type' => 'string',
          'label' => 'Assigned To',
          'section' => 'workflow',
          'order' => 2,
          'ui_component' => 'user_select'
        }
        
        fields << {
          'name' => 'created_by',
          'type' => 'string',
          'label' => 'Created By',
          'section' => 'workflow',
          'order' => 3,
          'visibility' => 'read_only'
        }
      end
      
      # Approval fields
      if has_approval_workflow?(answers)
        fields << {
          'name' => 'reviewed_by',
          'type' => 'string',
          'label' => 'Reviewed By',
          'section' => 'workflow',
          'order' => 4,
          'visibility' => 'read_only',
          'show_when' => { 'field' => 'status', 'in' => ['approved', 'rejected'] }
        }
        
        fields << {
          'name' => 'review_notes',
          'type' => 'text',
          'label' => 'Review Notes',
          'section' => 'workflow',
          'order' => 5,
          'show_when' => { 'field' => 'status', 'in' => ['rejected', 'pending_review'] }
        }
      end
      
      # Analytics fields (system managed)
      if has_analytics?(answers)
        %w[impressions engagement clicks].each_with_index do |metric, i|
          fields << {
            'name' => metric,
            'type' => 'integer',
            'label' => metric.titleize,
            'section' => 'metrics',
            'order' => i + 1,
            'visibility' => 'read_only',
            'default' => 0
          }
        end
      end
      
      # Notes field
      fields << {
        'name' => 'notes',
        'type' => 'text',
        'label' => 'Internal Notes',
        'section' => 'advanced',
        'order' => 1,
        'visibility' => 'edit_only'
      }
      
      fields
    end
    
    def generate_canvases_for_module(name, fields, answers)
      canvases = []
      
      # List view (always)
      display_fields = fields.select { |f| 
        f['section'] == 'content' || f['name'] == 'status' 
      }.first(5).map { |f| f['name'] }
      
      canvases << {
        'type' => 'list',
        'name' => "All #{name}",
        'slug' => "#{name.parameterize.underscore}_list",
        'is_default' => true,
        'columns' => display_fields,
        'filters' => ['status'],
        'sorting' => [{ 'field' => 'created_at', 'direction' => 'desc' }]
      }
      
      # Form view
      sections = fields.map { |f| f['section'] }.uniq
      canvases << {
        'type' => 'form',
        'name' => "#{name.singularize} Editor",
        'slug' => "#{name.parameterize.underscore}_form",
        'layout' => sections.length > 2 ? 'tabbed' : 'single_column',
        'sections' => sections.map do |s|
          {
            'name' => s,
            'label' => s.titleize,
            'icon' => section_icon(s),
            'fields' => fields.select { |f| f['section'] == s }.map { |f| f['name'] }
          }
        end
      }
      
      # Calendar view if scheduling
      if has_scheduling?(answers)
        canvases << {
          'type' => 'calendar',
          'name' => "#{name} Calendar",
          'slug' => "#{name.parameterize.underscore}_calendar",
          'date_field' => 'scheduled_for',
          'title_field' => 'title',
          'color_field' => 'status'
        }
      end
      
      # Kanban view if workflow
      if has_approval_workflow?(answers) || fields.any? { |f| f['name'] == 'status' }
        canvases << {
          'type' => 'kanban',
          'name' => "#{name} Board",
          'slug' => "#{name.parameterize.underscore}_board",
          'column_field' => 'status',
          'card_fields' => ['title', 'assigned_to', 'scheduled_for'].compact
        }
      end
      
      canvases
    end
    
    def generate_actions_for_module(name, fields, answers)
      actions = []
      singular = name.singularize
      
      # Submit for review
      if has_approval_workflow?(answers)
        actions << {
          'name' => 'Submit for Review',
          'slug' => 'submit_for_review',
          'icon' => 'send',
          'style' => 'primary',
          'location' => 'toolbar',
          'show_when' => { 'field' => 'status', 'equals' => 'draft' },
          'behavior_type' => 'update_and_notify',
          'behavior_config' => {
            'updates' => { 'status' => 'pending_review' },
            'notify' => { 'role' => 'approver', 'template' => 'pending_review' }
          }
        }
        
        actions << {
          'name' => 'Approve',
          'slug' => 'approve',
          'icon' => 'check',
          'style' => 'success',
          'location' => 'toolbar',
          'show_when' => { 'field' => 'status', 'equals' => 'pending_review' },
          'requires_role' => { 'role' => 'approver' },
          'behavior_type' => 'update_and_notify',
          'behavior_config' => {
            'updates' => { 'status' => 'approved' },
            'notify' => { 'role' => 'creator', 'template' => 'approved' }
          }
        }
        
        actions << {
          'name' => 'Reject',
          'slug' => 'reject',
          'icon' => 'x',
          'style' => 'danger',
          'location' => 'toolbar',
          'show_when' => { 'field' => 'status', 'equals' => 'pending_review' },
          'requires_role' => { 'role' => 'approver' },
          'behavior_type' => 'modal_form',
          'behavior_config' => {
            'fields' => ['review_notes'],
            'on_submit' => {
              'type' => 'update_and_notify',
              'updates' => { 'status' => 'rejected' },
              'notify' => { 'role' => 'creator', 'template' => 'rejected' }
            }
          }
        }
      end
      
      # Schedule action
      if has_scheduling?(answers)
        actions << {
          'name' => 'Schedule',
          'slug' => 'schedule',
          'icon' => 'calendar',
          'style' => 'primary',
          'location' => 'toolbar',
          'show_when' => { 'field' => 'status', 'in' => ['draft', 'approved'] },
          'behavior_type' => 'modal_form',
          'behavior_config' => {
            'fields' => ['scheduled_for'],
            'on_submit' => {
              'type' => 'update',
              'updates' => { 'status' => 'scheduled' }
            }
          }
        }
      end
      
      # AI Write action if content module
      if is_content_module?(name, '')
        actions << {
          'name' => 'AI Write',
          'slug' => 'ai_write',
          'icon' => 'sparkles',
          'style' => 'outline',
          'location' => 'field',
          'target_field' => 'content',
          'behavior_type' => 'agent_assist',
          'behavior_config' => {
            'agent' => 'app_assistant',
            'prompt' => "Help me write content for this #{singular}"
          }
        }
      end
      
      # Archive action
      actions << {
        'name' => 'Archive',
        'slug' => 'archive',
        'icon' => 'archive',
        'style' => 'outline',
        'location' => 'toolbar',
        'show_when' => { 'field' => 'status', 'not_in' => ['archived'] },
        'behavior_type' => 'confirm',
        'behavior_config' => {
          'message' => "Are you sure you want to archive this #{singular}?",
          'on_confirm' => {
            'type' => 'update',
            'updates' => { 'status' => 'archived' }
          }
        }
      }
      
      actions
    end
    
    def generate_tools_for_module(name)
      singular = name.singularize.parameterize.underscore
      plural = name.parameterize.underscore
      
      [
        {
          'name' => "create_#{singular}",
          'description' => "Create a new #{singular}"
        },
        {
          'name' => "get_#{plural}",
          'description' => "Get #{name} with optional filters"
        },
        {
          'name' => "update_#{singular}",
          'description' => "Update a #{singular}"
        },
        {
          'name' => "delete_#{singular}",
          'description' => "Delete a #{singular}"
        }
      ]
    end
    
    def generate_workflow_blueprint(wf_def, answers)
      {
        'name' => wf_def['name'],
        'trigger' => wf_def['trigger'] || { 'type' => 'manual' },
        'conditions' => wf_def['conditions'] || [],
        'actions' => wf_def['actions'] || []
      }
    end
    
    def generate_approval_workflow(primary_module)
      return nil unless primary_module
      
      {
        'name' => 'Approval Notification',
        'trigger' => {
          'type' => 'field_change',
          'field' => 'status',
          'to' => 'pending_review'
        },
        'actions' => [
          {
            'type' => 'notify',
            'role' => 'approver',
            'template' => 'new_item_pending_review'
          }
        ]
      }
    end
    
    def generate_scheduling_workflow(primary_module)
      return nil unless primary_module
      
      {
        'name' => 'Process Scheduled Items',
        'trigger' => {
          'type' => 'scheduled',
          'cron' => '*/5 * * * *'
        },
        'conditions' => [
          { 'field' => 'status', 'equals' => 'scheduled' },
          { 'field' => 'scheduled_for', 'less_than' => 'now' }
        ],
        'actions' => [
          {
            'type' => 'update',
            'updates' => { 'status' => 'published' }
          },
          {
            'type' => 'notify',
            'role' => 'creator',
            'template' => 'item_published'
          }
        ]
      }
    end
    
    def generate_assistant_blueprint(app, modules_def, answers)
      primary_module = modules_def.first
      
      {
        'name' => "#{app.name} Assistant",
        'slug' => "#{app.slug}_assistant",
        'icon' => 'bot',
        'persona' => generate_assistant_persona(app, primary_module),
        'capabilities' => generate_assistant_capabilities(primary_module, answers),
        'tools' => modules_def.flat_map { |m| generate_tools_for_module(m['name'] || m[:name]) }
                              .map { |t| t['name'] }
      }
    end
    
    def generate_assistant_persona(app, primary_module)
      <<~PERSONA
        You are an expert assistant for the #{app.name} application.
        You help users manage their #{primary_module&.dig('name') || 'content'} effectively.
        
        You can:
        - Create, update, and find records
        - Provide suggestions and best practices
        - Analyze performance and suggest improvements
        - Answer questions about how to use the app
        
        Always be helpful, concise, and proactive in suggesting improvements.
      PERSONA
    end
    
    def generate_assistant_capabilities(primary_module, answers)
      caps = []
      
      caps << {
        'name' => 'Create Records',
        'description' => "Create new #{primary_module&.dig('name') || 'records'}"
      }
      
      caps << {
        'name' => 'Find & Filter',
        'description' => 'Search and filter records'
      }
      
      if is_content_module?(primary_module&.dig('name') || '', '')
        caps << {
          'name' => 'Write Content',
          'description' => 'Help write and improve content'
        }
      end
      
      if has_analytics?(answers)
        caps << {
          'name' => 'Analyze Performance',
          'description' => 'Review metrics and suggest improvements'
        }
      end
      
      caps
    end
    
    def generate_blueprint_summary(blueprint)
      modules = blueprint['modules'] || []
      workflows = blueprint['workflows'] || []
      assistant = blueprint['app_assistant']
      
      summary = []
      summary << "## 📦 Modules (#{modules.length})"
      modules.each do |m|
        fields_count = m['fields']&.length || 0
        canvases_count = m['canvases']&.length || 0
        actions_count = m['actions']&.length || 0
        
        summary << "- **#{m['name']}**: #{fields_count} fields, #{canvases_count} views, #{actions_count} actions"
      end
      
      if workflows.any?
        summary << "\n## ⚡ Workflows (#{workflows.length})"
        workflows.each do |w|
          summary << "- **#{w['name']}**"
        end
      end
      
      if assistant
        summary << "\n## 🤖 AI Assistant"
        summary << "- **#{assistant['name']}** will help you use this app"
      end
      
      summary.join("\n")
    end
    
    # Helper methods
    def has_approval_workflow?(answers)
      answers['workflow'].to_s.downcase.include?('approv') ||
        answers['approval'].present?
    end
    
    def has_scheduling?(answers)
      answers['scheduling'].present? ||
        answers['workflow'].to_s.downcase.include?('schedul')
    end
    
    def has_team_features?(answers)
      answers['users'].to_s.downcase.include?('team') ||
        answers['team_features'].present?
    end
    
    def has_analytics?(answers)
      answers['analytics'].present?
    end
    
    def is_content_module?(name, description)
      keywords = %w[post content article blog social media message email]
      text = "#{name} #{description}".downcase
      keywords.any? { |k| text.include?(k) }
    end
    
    def suggest_icon(name, description)
      text = "#{name} #{description}".downcase
      
      case
      when text.include?('social') || text.include?('post')
        'share-2'
      when text.include?('calendar') || text.include?('schedule')
        'calendar'
      when text.include?('media') || text.include?('image') || text.include?('video')
        'image'
      when text.include?('campaign')
        'target'
      when text.include?('analytic') || text.include?('report')
        'bar-chart'
      when text.include?('task') || text.include?('project')
        'check-square'
      when text.include?('inventory') || text.include?('product')
        'package'
      when text.include?('contact') || text.include?('customer')
        'users'
      else
        'grid'
      end
    end
    
    def suggest_color(module_name)
      colors = {
        'social' => '#1DA1F2',
        'media' => '#E1306C',
        'campaign' => '#6366F1',
        'calendar' => '#10B981',
        'task' => '#F59E0B',
        'inventory' => '#8B5CF6'
      }
      
      name = module_name.to_s.downcase
      colors.find { |k, _| name.include?(k) }&.last || '#6366F1'
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
    
    def parse_integrations(integrations_text)
      platforms = %w[linkedin facebook instagram twitter buffer hootsuite mailchimp hubspot]
      found = platforms.select { |p| integrations_text.to_s.downcase.include?(p) }
      
      found.map do |p|
        { 'platform' => p, 'operations' => ['publish', 'get_metrics'] }
      end
    end
  end
end

