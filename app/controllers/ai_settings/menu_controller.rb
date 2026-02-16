class AiSettings::MenuController < ApplicationController
  before_action :authenticate_user!
  before_action :set_space_and_config

  layout "customer_admin"

  def show
    redirect_to chat_mode_path, status: :moved_permanently
  end
  
  def update_platform_settings
    entity = current_user.entity
    return render json: { success: false, error: 'No entity' }, status: :unprocessable_entity unless entity
    
    # Update notification settings
    entity.slack_notifications_enabled = params[:slack_notifications_enabled] == 'true' || params[:slack_notifications_enabled] == '1'
    entity.slack_webhook_url = params[:slack_webhook_url] if params[:slack_webhook_url].present?
    entity.email_notifications_enabled = params[:email_notifications_enabled] == 'true' || params[:email_notifications_enabled] == '1'
    
    # Update other platform settings
    entity.default_ai_model = params[:default_ai_model] if params[:default_ai_model].present?
    entity.canvas_theme = params[:canvas_theme] if params[:canvas_theme].present?
    
    if entity.save
      respond_to do |format|
        format.html { redirect_to chat_mode_path, notice: "Platform settings updated successfully." }
        format.json { render json: { success: true } }
      end
    else
      respond_to do |format|
        format.html { redirect_to chat_mode_path, alert: "Failed to update settings." }
        format.json { render json: { success: false, errors: entity.errors.full_messages }, status: :unprocessable_entity }
      end
    end
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
        format.html { redirect_to chat_mode_path, notice: "Menu configuration saved successfully." }
        format.json { render json: { success: true, config: config.as_json } }
      end
    else
      respond_to do |format|
        format.html { redirect_to chat_mode_path, alert: "Failed to save menu configuration." }
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
      format.html { redirect_to chat_mode_path, notice: "Menu reset to defaults for #{space.titleize} space." }
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
      # Marketing - Customer acquisition and outreach
      { slug: 'landing_page_viewer', name: 'Landing Pages', icon: 'layout', category: 'Marketing', spaces: ['work'] },
      { slug: 'campaign_viewer', name: 'Campaigns', icon: 'mail', category: 'Marketing', spaces: ['work'] },
      { slug: 'email_template_viewer', name: 'Email Templates', icon: 'file-text', category: 'Marketing', spaces: ['work'] },
      { slug: 'contact_viewer', name: 'Contacts', icon: 'users', category: 'Marketing', spaces: ['work'] },
      { slug: 'form_submissions', name: 'Form Submissions', icon: 'inbox', category: 'Marketing', spaces: ['work'] },
      
      # Insights - Analytics and visualization
      { slug: 'analytics_dashboard', name: 'Analytics', icon: 'bar-chart-2', category: 'Insights', spaces: ['work'] },
      { slug: 'saved_visualizations', name: 'Saved Visualizations', icon: 'bookmark', category: 'Insights', spaces: ['work'] },
      { slug: 'pipeline_viewer', name: 'Sales Pipeline', icon: 'git-branch', category: 'Insights', spaces: ['work'] },
      { slug: 'sequence_manager', name: 'Email Sequences', icon: 'mail', category: 'Marketing', spaces: ['work'] },
      
      # Content - Documents and media
      { slug: 'document_viewer', name: 'Documents', icon: 'folder', category: 'Content', spaces: ['work'] },
      { slug: 'media_library', name: 'Media Library', icon: 'image', category: 'Content', spaces: ['work'] },
      
      # Productivity - Tasks and organization
      { slug: 'work_inbox', name: 'Work Inbox', icon: 'inbox', category: 'Productivity', spaces: ['work'] },
      { slug: 'scheduled_tasks', name: 'Scheduled Tasks', icon: 'clock', category: 'Productivity', spaces: ['work'] },
      { slug: 'parallel_tasks', name: 'Task Monitor', icon: 'activity', category: 'Productivity', spaces: ['work'] },
      { slug: 'notes', name: 'Notes', icon: 'edit-3', category: 'Productivity', spaces: ['work'] },
      { slug: 'reminders', name: 'Reminders', icon: 'bell', category: 'Productivity', spaces: ['work'] },
      { slug: 'bookmarks', name: 'Bookmarks', icon: 'bookmark', category: 'Productivity', spaces: ['work'] },
      
      # Design - Creation tools
      # Users describe what they want → AMOS builds it. No template browsing needed.
      { slug: 'my_creations', name: 'Created Assets', icon: 'folder-open', category: 'Design', spaces: ['work'] },
      # design_studio, workflow_designer, template_library, app_designer removed
      # — users just tell AMOS what to build and it creates + shows the right editor
      
      # Platform - Apps and modules
      { slug: 'module_manager', name: 'Installed Apps', icon: 'box', category: 'Apps', spaces: ['work'] },
      { slug: 'module_marketplace', name: 'App Store', icon: 'grid-2x2', category: 'Apps', spaces: ['work'] },
      # app_designer removed — use module_manager
      
      # Automation - Workflows and execution
      { slug: 'automation_dashboard', name: 'Automations', icon: 'zap', category: 'Automation', spaces: ['work'] },
      { slug: 'workflow_analytics', name: 'Workflow Analytics', icon: 'activity', category: 'Automation', spaces: ['work'] },
      { slug: 'execution_dashboard', name: 'Execution Monitor', icon: 'gauge', category: 'Automation', spaces: ['work'] },
      
      # System - Configuration
      { slug: 'integrations_manager', name: 'Integrations', icon: 'plug', category: 'System', spaces: ['work'] },
      { slug: 'operations_dashboard', name: 'Operations Center', icon: 'settings', category: 'System', spaces: ['work'] },
      { slug: 'support_tickets', name: 'Support Tickets', icon: 'ticket', category: 'System', spaces: ['work'] },
      
      # Collaboration - Team features
      { slug: 'team_channels', name: 'Team Channels', icon: 'message-circle', category: 'Collaboration', spaces: ['work'] }
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
