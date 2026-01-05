# frozen_string_literal: true

# RequestModuleTool
#
# Tool for Amos (Scout) to request a new module from the Platform Factory.
# This is the entry point for users asking for custom functionality.
#
class Tools::RequestModuleTool < Tools::BaseTool
  def self.metadata
    {
      name: 'request_module',
      description: 'Request the Platform Factory to build a new custom module. Use this when users ask for functionality that doesn\'t exist yet, like "I need inventory tracking" or "Build me a project management system".',
      category: 'platform_factory',
      input_schema: {
        type: 'object',
        properties: {
          module_name: {
            type: 'string',
            description: 'Name for the module (e.g., "Inventory Management", "Project Tracker")'
          },
          requirements: {
            type: 'string',
            description: 'Detailed requirements for what the module should do'
          },
          features: {
            type: 'array',
            items: { type: 'string' },
            description: 'List of specific features needed'
          },
          integrations: {
            type: 'array',
            items: { type: 'string' },
            description: 'External services to integrate with (optional)'
          },
          ui_modes: {
            type: 'array',
            items: { type: 'string', enum: %w[simple advanced] },
            description: 'Which UI modes to support'
          }
        },
        required: %w[module_name requirements]
      }
    }
  end

  def execute(args)
    log_execution(args)

    module_name = get_arg(args, :module_name)
    requirements = get_arg(args, :requirements)
    features = get_arg(args, :features, [])
    integrations = get_arg(args, :integrations, [])
    ui_modes = get_arg(args, :ui_modes, ['simple'])

    return error_response('Module name is required') if module_name.blank?
    return error_response('Requirements are required') if requirements.blank?

    # Create the module record in draft state
    app_module = create_draft_module(module_name, requirements, features, ui_modes)

    # Build the specification for Platform Factory
    spec = build_module_spec(
      app_module: app_module,
      requirements: requirements,
      features: features,
      integrations: integrations,
      ui_modes: ui_modes
    )

    # Queue the Platform Factory execution
    execution = queue_platform_factory(app_module, spec)

    success_response(
      module_id: app_module.id,
      module_slug: app_module.slug,
      execution_id: execution&.id,
      status: 'queued',
      message: "Module request submitted! The Platform Factory is now building '#{module_name}'.",
      estimated_time: '2-5 minutes',
      next_step: 'I\'ll notify you when it\'s ready. You can check progress by asking "What\'s the status of my module?"'
    )
  end

  private

  def create_draft_module(module_name, requirements, features, ui_modes)
    slug = module_name.parameterize.underscore
    
    # Ensure unique slug
    counter = 1
    base_slug = slug
    while AppModule.exists?(entity: entity, slug: slug)
      slug = "#{base_slug}_#{counter}"
      counter += 1
    end

    AppModule.create!(
      entity: entity,
      created_by: user,
      slug: slug,
      name: module_name,
      description: requirements.truncate(500),
      status: 'draft',
      author_type: 'amos',
      visibility: 'entity_private',
      ui_modes: {
        'simple' => ui_modes.include?('simple'),
        'advanced' => ui_modes.include?('advanced'),
        'simple_default' => ui_modes.first == 'simple'
      },
      components: {
        'canvases' => [],
        'data_models' => [],
        'tools' => [],
        'webhooks' => [],
        'scheduled_tasks' => []
      },
      metadata: {
        'requested_features' => features,
        'requested_at' => Time.current.iso8601
      }
    )
  end

  def build_module_spec(app_module:, requirements:, features:, integrations:, ui_modes:)
    {
      module_id: app_module.id,
      module_slug: app_module.slug,
      module_name: app_module.name,
      requirements: requirements,
      features: features,
      integrations: integrations,
      ui_modes: ui_modes,
      entity_id: entity.id,
      user_id: user.id,
      existing_models: get_existing_models,
      phase: 'full_build'  # design → generate → deploy → test
    }
  end

  def get_existing_models
    # Get models the user already has access to
    %w[Contact Campaign LandingPage Opportunity Activity] + 
      entity.app_modules.active.flat_map(&:data_models_list)
  end

  def queue_platform_factory(app_module, spec)
    # Find the Platform Factory agent
    platform_factory = AgentPlugin.find_by(slug: 'platform_factory')
    
    unless platform_factory
      Rails.logger.warn "[RequestModuleTool] Platform Factory agent not found"
      return nil
    end

    # Create an execution
    execution = AgentPluginExecution.create!(
      agent_plugin: platform_factory,
      user: user,
      status: 'running',
      input_context: {
        task_type: 'build_module',
        specification: spec,
        triggered_by: 'request_module_tool',
        app_module_id: app_module.id
      }
    )

    # Queue the job
    PlatformFactoryJob.perform_later(execution.id, spec)

    # Update module status
    app_module.start_design!

    execution
  end
end


