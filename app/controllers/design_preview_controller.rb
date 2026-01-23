# frozen_string_literal: true

# DesignPreviewController - Serves preview pages for web apps, websites, and landing pages
#
# This controller provides iFrame-friendly previews for the Design Space canvas.
# It handles:
# - Web app previews (with module data)
# - Website page previews
# - Landing page previews
# - Component previews (individual Bootstrap components)
#
class DesignPreviewController < ApplicationController
  include LandingPageRendering
  
  before_action :authenticate_user!
  before_action :set_entity
  layout 'preview'

  # GET /design_preview/web_app/:id
  def web_app
    @web_app = WebApp.find_by(id: params[:id], entity: @entity)
    return render_not_found unless @web_app

    @website = @web_app.website
    @modules = @web_app.app_modules
    
    render :web_app
  end

  # GET /design_preview/website/:id
  def website
    @website = Website.find_by(id: params[:id], entity: @entity)
    return render_not_found unless @website

    @page = @website.website_pages.find_by(slug: params[:page] || 'index')
    @page ||= @website.website_pages.first
    
    render :website_page
  end

  # GET /design_preview/landing_page/:id
  def landing_page
    @landing_page = LandingPage.find_by(id: params[:id], entity: @entity)
    return render_not_found unless @landing_page

    # Prepare HTML with refreshed signed URLs
    @prepared_html = prepare_landing_page_html(@landing_page)
    
    render :landing_page
  end

  # GET /design_preview/component
  # Params: type, variant, design_system, data (JSON)
  def component
    @type = params[:type]&.to_sym || :hero
    @variant = params[:variant] || 'gradient'
    @design_system = params[:design_system]&.to_sym || :modern
    @component_data = params[:data].present? ? JSON.parse(params[:data]) : {}

    # Get the template
    @template_path = "components/bootstrap/#{@type}/#{@variant}"
    
    # Generate CSS variables for the design system
    @css_variables = Agents::FrontendDesignExpert.generate_css_variables(@design_system)
    
    render :component
  rescue JSON::ParserError
    @component_data = {}
    render :component
  end

  # GET /design_preview/module/:slug
  # Preview a module's canvas/UI
  def app_module
    @app_module = AppModule.find_by(slug: params[:slug], entity: @entity)
    return render_not_found unless @app_module

    @canvas = @app_module.module_canvases.find_by(canvas_type: 'list') || @app_module.module_canvases.first
    @records = load_module_records(@app_module)
    
    render :app_module
  end

  # GET /design_preview/automation/:id
  # Preview an automation's workflow
  def automation
    @automation = AutomationCode.find_by(id: params[:id], entity: @entity)
    return render_not_found unless @automation

    @nodes = build_workflow_nodes(@automation)
    
    render :automation
  end

  private

  def set_entity
    @entity = current_user.entity
  end

  def render_not_found
    render html: '<div class="d-flex align-items-center justify-content-center h-100 text-muted"><p>Not found</p></div>'.html_safe, 
           layout: 'preview', 
           status: :not_found
  end

  def load_module_records(app_module, limit: 10)
    return [] unless app_module.model_code&.deployed?

    begin
      model_class = Modules::DynamicModelLoader.instance.get_model(app_module.model_code)
      return [] unless model_class

      model_class.where(entity_id: @entity.id).limit(limit).order(created_at: :desc)
    rescue => e
      Rails.logger.error "Failed to load module records: #{e.message}"
      []
    end
  end

  def build_workflow_nodes(automation)
    nodes = []
    
    # Add trigger node
    nodes << {
      id: 'trigger',
      type: 'trigger',
      label: trigger_label(automation),
      config: automation.trigger_config
    }

    # Parse the code to extract actions
    code = automation.code || ''
    
    if code.include?('send_slack_message')
      nodes << { id: 'slack', type: 'notification', label: 'Send Slack Message' }
    end

    if code.include?('send_email')
      nodes << { id: 'email', type: 'notification', label: 'Send Email' }
    end

    if code.include?('http_post') || code.include?('http_get')
      nodes << { id: 'http', type: 'integration', label: 'HTTP Request' }
    end

    if code.include?('update_record')
      nodes << { id: 'update', type: 'action', label: 'Update Record' }
    end

    if code.include?('create_record')
      nodes << { id: 'create', type: 'action', label: 'Create Record' }
    end

    nodes
  end

  def trigger_label(automation)
    case automation.trigger_type
    when 'record_created' then "When #{automation.trigger_config['model'] || 'record'} is created"
    when 'record_updated' then "When #{automation.trigger_config['model'] || 'record'} is updated"
    when 'status_changed' then "When status changes to #{automation.trigger_config['to']}"
    when 'field_changed' then "When #{automation.trigger_config['field']} changes"
    when 'schedule' then "On schedule: #{automation.trigger_config['schedule']}"
    when 'webhook' then "Webhook received"
    when 'form_submit' then "Form submitted"
    else automation.trigger_type.titleize
    end
  end
end

