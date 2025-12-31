# frozen_string_literal: true

# RegisterModuleCanvasTool
#
# Platform Factory tool that registers a module canvas
# so it can be loaded by the Scout canvas system.
#
class Tools::RegisterModuleCanvasTool < Tools::BaseTool
  def self.metadata
    {
      name: 'register_module_canvas',
      description: 'Registers a module canvas so it becomes available in the UI. Adds the canvas to the entity\'s available views and optionally to the navigation menu.',
      category: 'platform_factory',
      input_schema: {
        type: 'object',
        properties: {
          module_slug: {
            type: 'string',
            description: 'Slug of the module'
          },
          canvas_slug: {
            type: 'string',
            description: 'Slug of the canvas to register'
          },
          add_to_menu: {
            type: 'boolean',
            description: 'Whether to add this canvas to the navigation menu'
          },
          menu_label: {
            type: 'string',
            description: 'Label to show in the menu (defaults to canvas name)'
          },
          menu_icon: {
            type: 'string',
            description: 'Lucide icon name for the menu item'
          },
          set_as_default: {
            type: 'boolean',
            description: 'Whether this should be the default canvas for the module'
          }
        },
        required: %w[module_slug canvas_slug]
      }
    }
  end

  def execute(args)
    log_execution(args)

    module_slug = get_arg(args, :module_slug)
    canvas_slug = get_arg(args, :canvas_slug)
    add_to_menu = get_arg(args, :add_to_menu, true)
    menu_label = get_arg(args, :menu_label)
    menu_icon = get_arg(args, :menu_icon, 'box')
    set_as_default = get_arg(args, :set_as_default, false)

    return error_response('Module slug is required') if module_slug.blank?
    return error_response('Canvas slug is required') if canvas_slug.blank?

    # Find the module
    app_module = AppModule.find_by(entity: entity, slug: module_slug)
    return error_response("Module not found: #{module_slug}") unless app_module

    # Find the canvas
    canvas = ModuleCanvas.find_by(app_module: app_module, slug: canvas_slug)
    return error_response("Canvas not found: #{canvas_slug}") unless canvas

    # Update canvas if setting as default
    if set_as_default
      # Unset other defaults
      app_module.module_canvases.update_all(is_default: false)
      canvas.update!(is_default: true)
    end

    # Register the canvas type with Scout's canvas system
    register_with_scout(app_module, canvas)

    # Add to menu if requested
    if add_to_menu
      add_canvas_to_menu(app_module, canvas, menu_label, menu_icon)
    end

    # Get the full canvas type identifier
    full_canvas_type = "module_#{module_slug}_#{canvas_slug}"

    success_response(
      canvas_id: canvas.id,
      full_canvas_type: full_canvas_type,
      registered: true,
      in_menu: add_to_menu,
      is_default: canvas.is_default,
      message: "Canvas '#{canvas.name}' registered successfully",
      load_command: "load_canvas(canvas_name: '#{full_canvas_type}')"
    )
  end

  private

  def register_with_scout(app_module, canvas)
    # The canvas is now registered by virtue of existing in the database
    # The ScoutController will dynamically look up module canvases
    
    # Update the module's component list if needed
    canvases = app_module.canvases_list
    unless canvases.include?(canvas.slug)
      canvases << canvas.slug
      app_module.update!(components: app_module.components.merge('canvases' => canvases))
    end

    # Log the registration
    Rails.logger.info "[PlatformFactory] Registered canvas: #{app_module.slug}/#{canvas.slug}"
  end

  def add_canvas_to_menu(app_module, canvas, label, icon)
    # Get current user's menu configuration or create new one
    menu_config = user.user_menu_configuration || user.create_user_menu_configuration!
    
    # Add the module canvas to custom items
    custom_items = menu_config.custom_items || []
    
    menu_item = {
      'id' => "module_#{app_module.slug}_#{canvas.slug}",
      'label' => label || canvas.name,
      'icon' => icon || app_module.icon || 'box',
      'canvas_type' => "module_#{app_module.slug}_#{canvas.slug}",
      'module_slug' => app_module.slug,
      'canvas_slug' => canvas.slug,
      'space' => 'work'  # Modules appear in work space by default
    }

    # Update or add the menu item
    existing_index = custom_items.find_index { |item| item['id'] == menu_item['id'] }
    if existing_index
      custom_items[existing_index] = menu_item
    else
      custom_items << menu_item
    end

    menu_config.update!(custom_items: custom_items)
    
    Rails.logger.info "[PlatformFactory] Added menu item: #{menu_item['label']}"
  end
end


