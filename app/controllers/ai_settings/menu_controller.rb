class AiSettings::MenuController < ApplicationController
  before_action :authenticate_user!
  before_action :set_space_and_config

  layout "customer_admin"

  def show
    @all_menu_items = available_menu_items
    @spaces = SpaceDefinition.enabled.ordered
  end

  def update
    space = params[:space] || current_user.active_space
    config = current_user.menu_config_for_space(space)

    # visible_items comes from checkboxes - always set it (empty array if nothing checked)
    # Use params.fetch to get empty array if key missing
    config.visible_items = params.fetch(:visible_items, [])
    
    # Calculate hidden_items as items that are NOT in visible_items
    all_item_slugs = available_menu_items.map { |i| i[:slug] }
    config.hidden_items = all_item_slugs - config.visible_items

    if params[:pinned_items].present?
      config.pinned_items = params[:pinned_items]
    end

    if config.save
      respond_to do |format|
        format.html { redirect_to ai_settings_menu_path(space: space), notice: "Menu configuration saved successfully." }
        format.json { render json: { success: true, config: config.as_json } }
      end
    else
      respond_to do |format|
        format.html { redirect_to ai_settings_menu_path(space: space), alert: "Failed to save menu configuration." }
        format.json { render json: { success: false, errors: config.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def toggle_item
    item_slug = params[:item]
    action = params[:action_type] # show, hide, pin, unpin
    space = params[:space] || current_user.active_space

    config = current_user.menu_config_for_space(space)

    success = case action
    when 'show' then config.show_item(item_slug)
    when 'hide' then config.hide_item(item_slug)
    when 'pin' then config.pin_item(item_slug)
    when 'unpin' then config.unpin_item(item_slug)
    else false
    end

    render json: { success: success, config: config.as_json }
  end

  def reset
    space = params[:space] || current_user.active_space
    config = current_user.menu_config_for_space(space)
    config.reset_to_defaults!

    respond_to do |format|
      format.html { redirect_to ai_settings_menu_path, notice: "Menu reset to defaults for #{space.titleize} space." }
      format.json { render json: { success: true, config: config.as_json } }
    end
  end

  private

  def set_space_and_config
    @current_space = params[:space] || current_user.active_space
    @config = current_user.menu_config_for_space(@current_space)
  end

  def available_menu_items
    items = [
      # Marketing
      { slug: 'landing_pages', name: 'Landing Pages', icon: 'layout', category: 'Marketing', spaces: ['work'] },
      { slug: 'campaigns', name: 'Campaigns', icon: 'mail', category: 'Marketing', spaces: ['work'] },
      { slug: 'email_templates', name: 'Email Templates', icon: 'file-text', category: 'Marketing', spaces: ['work'] },
      { slug: 'contacts', name: 'Contacts', icon: 'users', category: 'Marketing', spaces: ['work'] },
      { slug: 'contact_groups', name: 'Contact Groups', icon: 'user-plus', category: 'Marketing', spaces: ['work'] },
      
      # Insights
      { slug: 'analytics', name: 'Analytics', icon: 'bar-chart-2', category: 'Insights', spaces: ['work'] },
      { slug: 'saved_visualizations', name: 'Saved Visualizations', icon: 'bookmark', category: 'Insights', spaces: ['work'] },
      
      # Content
      { slug: 'documents', name: 'Documents', icon: 'folder', category: 'Content', spaces: ['personal', 'work'] },
      
      # Productivity
      { slug: 'tasks', name: 'Tasks', icon: 'check-square', category: 'Productivity', spaces: ['personal', 'work', 'team'] },
      { slug: 'work_inbox', name: 'Work Inbox', icon: 'inbox', category: 'Productivity', spaces: ['personal', 'work', 'team'] },
      { slug: 'scheduled_tasks', name: 'Scheduled Tasks', icon: 'clock', category: 'Productivity', spaces: ['personal', 'work'] },
      { slug: 'parallel_tasks', name: 'Task Monitor', icon: 'activity', category: 'Productivity', spaces: ['work'] },
      { slug: 'reminders', name: 'Reminders', icon: 'bell', category: 'Productivity', spaces: ['personal'] },
      { slug: 'notes', name: 'Notes', icon: 'edit-3', category: 'Productivity', spaces: ['personal'] },
      
      # Platform
      { slug: 'module_manager', name: 'Installed Modules', icon: 'box', category: 'Platform', spaces: ['work'] },
      { slug: 'module_marketplace', name: 'Module Marketplace', icon: 'shopping-bag', category: 'Platform', spaces: ['work'] },
      { slug: 'app_designer', name: 'App Designer', icon: 'layers', category: 'Platform', spaces: ['work'] },
      { slug: 'execution_dashboard', name: 'Execution Dashboard', icon: 'gauge', category: 'Platform', spaces: ['work'] },
      
      # System
      { slug: 'integrations_manager', name: 'Integrations', icon: 'plug', category: 'System', spaces: ['work', 'team'] },
      { slug: 'agent_marketplace', name: 'Agent Marketplace', icon: 'bot', category: 'System', spaces: ['work', 'team'] },
      { slug: 'tools', name: 'Custom Tools', icon: 'wrench', category: 'System', spaces: ['work'] },
      
      # Collaboration
      { slug: 'team_channels', name: 'Team Channels', icon: 'message-circle', category: 'Collaboration', spaces: ['team'] },
      { slug: 'shared_tasks', name: 'Shared Tasks', icon: 'clipboard-list', category: 'Collaboration', spaces: ['team'] },
      { slug: 'notifications', name: 'Notifications', icon: 'bell', category: 'Collaboration', spaces: ['team'] }
    ]
    
    # Add module canvases dynamically
    if current_user.entity
      current_user.entity.app_modules.active.each do |app_module|
        app_module.module_canvases.each do |canvas|
          items << {
            slug: "module_#{app_module.slug}_#{canvas.slug}",
            name: "#{app_module.name}: #{canvas.name}",
            icon: app_module.icon || 'box',
            category: 'Custom Modules',
            spaces: ['work'],
            canvas_type: canvas.full_canvas_type,
            module_slug: app_module.slug,
            canvas_slug: canvas.slug
          }
        end
      end
    end
    
    items
  end
end
