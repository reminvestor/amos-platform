# frozen_string_literal: true

class ModulesController < ApplicationController
  include Authorizable
  before_action :authenticate_user!
  before_action :set_module, only: %i[show update destroy activate deactivate share unshare]
  before_action :authorize_destroy!, only: [:destroy]

  # GET /modules
  def index
    # Only show modules visible to current user (respects user_private, entity_shared, etc.)
    @modules = current_entity.app_modules.visible_to(current_user).order(created_at: :desc)
    
    respond_to do |format|
      format.html
      format.json do
        render json: {
          modules: @modules.map { |m| module_json(m) },
          total: @modules.count
        }
      end
    end
  end

  # GET /modules/:slug
  def show
    respond_to do |format|
      format.html
      format.json { render json: module_json(@module, include_details: true) }
    end
  end

  # POST /modules
  def create
    @module = current_entity.app_modules.build(module_params)
    @module.created_by = current_user
    @module.author_type = 'user'

    if @module.save
      render json: {
        success: true,
        module: module_json(@module)
      }, status: :created
    else
      render json: {
        success: false,
        errors: @module.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /modules/:slug
  def update
    if @module.update(module_params)
      render json: {
        success: true,
        module: module_json(@module)
      }
    else
      render json: {
        success: false,
        errors: @module.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # DELETE /modules/:slug
  def destroy
    @module.destroy
    
    render json: {
      success: true,
      message: "Module '#{@module.name}' deleted successfully"
    }
  end

  # POST /modules/:slug/activate
  def activate
    @module.activate!
    
    render json: {
      success: true,
      message: "Module '#{@module.name}' is now active",
      module: module_json(@module)
    }
  end

  # POST /modules/:slug/deactivate
  def deactivate
    @module.disable!
    
    render json: {
      success: true,
      message: "Module '#{@module.name}' has been deactivated",
      module: module_json(@module)
    }
  end

  # GET /modules/:slug/canvases
  def canvases
    @module = current_entity.app_modules.visible_to(current_user).find_by!(slug: params[:slug])
    
    render json: {
      canvases: @module.module_canvases.map do |canvas|
        {
          id: canvas.id,
          slug: canvas.slug,
          name: canvas.name,
          canvas_type: canvas.canvas_type,
          ui_mode: canvas.ui_mode,
          is_default: canvas.is_default,
          full_type: canvas.full_canvas_type
        }
      end
    }
  end

  # GET /modules/:slug/canvas/:canvas_slug
  def load_canvas
    @module = current_entity.app_modules.visible_to(current_user).find_by!(slug: params[:slug])
    canvas = @module.module_canvases.find_by!(slug: params[:canvas_slug])
    
    # Render the canvas
    render json: canvas.to_canvas_response
  end

  # GET /modules/installed
  def installed
    # Only show active modules visible to current user
    @modules = current_entity.app_modules.visible_to(current_user).active.order(:name)
    
    render json: {
      modules: @modules.map { |m| module_json(m) },
      total: @modules.count
    }
  end

  # POST /modules/:slug/share - Share module with team
  def share
    unless @module.editable_by?(current_user)
      return render json: { success: false, error: 'You do not have permission to share this module' }, status: :forbidden
    end

    if @module.share_with_team!
      # Notify Hub about the shared module
      begin
        Hub::ModuleBridgeService.new(app_module: @module).on_module_shared(shared_by: current_user)
      rescue => e
        Rails.logger.warn "[ModulesController] Hub notification failed (non-fatal): #{e.message}"
      end

      render json: {
        success: true,
        message: "#{@module.name} is now shared with your team",
        module: module_json(@module)
      }
    else
      render json: { success: false, error: 'Module is already shared' }, status: :unprocessable_entity
    end
  end

  # POST /modules/:slug/unshare - Make module private again
  def unshare
    unless @module.created_by_id == current_user.id
      return render json: { success: false, error: 'Only the creator can make this module private' }, status: :forbidden
    end

    if @module.make_private!
      render json: {
        success: true,
        message: "#{@module.name} is now private",
        module: module_json(@module)
      }
    else
      render json: { success: false, error: 'Could not make module private' }, status: :unprocessable_entity
    end
  end

  # POST /modules/install_template
  def install_template
    template_key = params[:template]
    
    installer = Modules::TemplateInstaller.new(entity: current_entity, user: current_user)
    result = installer.install(template_key)
    
    if result[:success]
      render json: result
    else
      render json: { success: false, message: result[:error] }, status: :unprocessable_entity
    end
  end

  # GET /modules/templates
  def templates
    installer = Modules::TemplateInstaller.new(entity: current_entity, user: current_user)
    
    render json: {
      templates: installer.available_templates
    }
  end

  # POST /modules/:slug/export
  def export
    @module = current_entity.app_modules.visible_to(current_user).find_by!(slug: params[:slug])
    
    exporter = Modules::ModuleExporter.new(@module)
    export_data = exporter.export
    
    render json: export_data
  end

  # POST /modules/import
  def import
    import_data = params[:module_data] || JSON.parse(request.body.read)
    
    importer = Modules::ModuleImporter.new(
      entity: current_entity,
      user: current_user,
      export_data: import_data
    )
    
    result = importer.import
    
    if result[:success]
      render json: {
        success: true,
        module: module_json(result[:module]),
        components: result[:components],
        message: "Module imported successfully"
      }
    else
      render json: { success: false, error: result[:error] }, status: :unprocessable_entity
    end
  end

  private

  def set_module
    # Find module within entity, but also verify visibility
    @module = current_entity.app_modules.visible_to(current_user).find_by!(slug: params[:slug])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Module not found' }, status: :not_found
  end

  def module_params
    params.require(:app_module).permit(
      :name, :slug, :description, :icon, :status, :visibility,
      :show_in_menu, :menu_order, :menu_parent,
      components: {},
      ui_modes: {},
      dependencies: [],
      permissions: [],
      metadata: {}
    )
  end

  def module_json(app_module, include_details: false)
    data = {
      id: app_module.id,
      slug: app_module.slug,
      name: app_module.name,
      description: app_module.description,
      icon: app_module.icon || 'box',
      version: app_module.version,
      status: app_module.status,
      author_type: app_module.author_type,
      visibility: app_module.visibility,
      visibility_label: visibility_label(app_module.visibility),
      is_owner: app_module.created_by_id == current_user.id,
      can_edit: app_module.editable_by?(current_user),
      can_share: app_module.user_private? && app_module.created_by_id == current_user.id,
      can_unshare: app_module.entity_visible? && app_module.created_by_id == current_user.id,
      created_by_name: app_module.created_by&.full_name || 'System',
      created_at: app_module.created_at.iso8601,
      updated_at: app_module.updated_at.iso8601,
      deployed_at: app_module.deployed_at&.iso8601,
      components_summary: {
        canvases: app_module.canvases_list.count,
        models: app_module.data_models_list.count,
        tools: app_module.tools_list.count,
        webhooks: app_module.webhooks_list.count
      }
    }

    if include_details
      data.merge!(
        components: app_module.components,
        ui_modes: app_module.ui_modes,
        dependencies: app_module.dependencies,
        permissions: app_module.permissions,
        show_in_menu: app_module.show_in_menu,
        menu_order: app_module.menu_order,
        test_results: app_module.test_results,
        canvases: app_module.module_canvases.map do |c|
          { slug: c.slug, name: c.name, type: c.canvas_type, is_default: c.is_default }
        end,
        models: app_module.module_codes.models.map do |m|
          { name: m.name, status: m.status }
        end,
        webhooks: app_module.module_webhooks.map do |w|
          { slug: w.slug, event: w.event_name, status: w.status }
        end
      )
    end

    data
  end

  def visibility_label(visibility)
    case visibility
    when 'user_private'
      'Private (only you)'
    when 'entity_private', 'entity_shared'
      'Shared with team'
    when 'public'
      'Public'
    else
      visibility.titleize
    end
  end
end

