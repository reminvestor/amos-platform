# frozen_string_literal: true

module Tools
  # InstallAppTemplateTool - Installs a pre-built app template
  #
  class InstallAppTemplateTool < BaseTool
    def self.metadata
      {
        name: "install_app_template",
        description: "Install a pre-built app template. Creates a fully functional app from a template.",
        category: "app_building",
        input_schema: {
          type: "object",
          properties: {
            template_key: {
              type: "string",
              enum: ["social_media_manager", "project_tracker", "inventory_manager", "event_planner"],
              description: "Template to install: social_media_manager, project_tracker, inventory_manager, event_planner"
            },
            custom_name: { type: "string", description: "Optional: custom name for the app (defaults to template name)" }
          },
          required: ["template_key"]
        }
      }
    end
    
    AVAILABLE_TEMPLATES = {
      'social_media_manager' => {
        name: 'Social Media Manager',
        description: 'Plan, create, schedule, and analyze social media content',
        modules: ['Posts', 'Campaigns', 'Media Library'],
        features: ['Content Calendar', 'Approval Workflow', 'AI Writing Assistant', 'Performance Metrics']
      },
      'project_tracker' => {
        name: 'Project Tracker',
        description: 'Manage projects, tasks, and team assignments',
        modules: ['Projects', 'Tasks', 'Milestones'],
        features: ['Kanban Board', 'Timeline View', 'Team Assignment', 'Progress Tracking']
      },
      'inventory_manager' => {
        name: 'Inventory Manager',
        description: 'Track products, stock levels, and orders',
        modules: ['Products', 'Inventory', 'Orders'],
        features: ['Stock Alerts', 'Reorder Points', 'Supplier Tracking', 'Reports']
      },
      'event_planner' => {
        name: 'Event Planner',
        description: 'Plan and manage events, guests, and RSVPs',
        modules: ['Events', 'Guests', 'Tasks'],
        features: ['Calendar View', 'RSVP Tracking', 'Task Checklists', 'Budget Tracking']
      }
    }.freeze
    
    def execute(args)
      log_execution(args)
      
      template_key = get_arg(args, :template_key)&.to_s&.downcase&.strip
      custom_name = get_arg(args, :custom_name)
      
      if error = validate_required_args(args, [:template_key])
        return error
      end
      
      template = AVAILABLE_TEMPLATES[template_key]
      unless template
        return error_response(
          "Unknown template: #{template_key}",
          available_templates: AVAILABLE_TEMPLATES.map { |k, v| { key: k, name: v[:name], description: v[:description] } },
          suggestion: "Available templates: #{AVAILABLE_TEMPLATES.keys.join(', ')}"
        )
      end
      
      # Check if already installed
      existing = App.find_by(entity_id: entity.id, slug: template_key)
      if existing
        return error_response(
          "#{template[:name]} is already installed",
          app_id: existing.id,
          status: existing.status,
          suggestion: existing.active? ? "Open it with: 'Show me #{template[:name]}'" : "Continue from where you left off"
        )
      end
      
      # Install the template
      app = case template_key
            when 'social_media_manager'
              require_relative '../../../../db/seeds/app_templates/social_media_manager'
              AppTemplates::SocialMediaManager.install(entity: entity, user: user)
            else
              # For templates without full implementation, create a blueprint-only app
              create_from_template(template_key, template, custom_name)
            end
      
      success_response(
        app_id: app.id,
        app_name: app.name,
        status: app.status,
        template_used: template_key,
        modules: app.app_modules.map(&:name),
        load_canvas: "app_designer",
        canvas_data: { app_id: app.id },
        message: <<~MSG
          🎉 **#{app.name}** has been installed!
          
          **Modules:** #{app.app_modules.map(&:name).join(', ')}
          **Status:** #{app.status.titleize}
          
          #{app.preview? ? "The app is ready to test! Would you like to open it?" : "The app is being set up..."}
        MSG
      )
    rescue => e
      Rails.logger.error "[InstallAppTemplate] Error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      error_response("Failed to install template: #{e.message}")
    end
    
    private
    
    def create_from_template(template_key, template, custom_name)
      # Create a basic app that can be built later
      app = App.create!(
        entity: entity,
        created_by: user,
        name: custom_name || template[:name],
        slug: template_key,
        description: template[:description],
        status: 'planning',
        blueprint: generate_basic_blueprint(template),
        intent: {
          'source' => 'template',
          'template_name' => template_key,
          'installed_at' => Time.current.iso8601
        }
      )
      
      app
    end
    
    def generate_basic_blueprint(template)
      {
        'app' => {
          'name' => template[:name],
          'description' => template[:description]
        },
        'modules' => template[:modules].map.with_index do |mod_name, i|
          {
            'name' => mod_name,
            'slug' => mod_name.parameterize.underscore,
            'is_primary' => i == 0,
            'fields' => [
              { 'name' => 'title', 'type' => 'string', 'required' => true, 'section' => 'content' },
              { 'name' => 'description', 'type' => 'text', 'section' => 'content' },
              { 'name' => 'status', 'type' => 'select', 'options' => ['draft', 'active', 'completed'], 'default' => 'draft', 'section' => 'workflow' }
            ],
            'canvases' => [
              { 'type' => 'list', 'name' => "All #{mod_name}", 'is_default' => true },
              { 'type' => 'form', 'name' => "#{mod_name.singularize} Editor" }
            ],
            'actions' => []
          }
        end,
        'workflows' => [],
        'app_assistant' => nil
      }
    end
  end
end

