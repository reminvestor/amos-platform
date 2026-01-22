# frozen_string_literal: true

# DesignSpaceService - Orchestrates the full design and building flow
#
# This service connects all the pieces of the Design Space:
# - Application planning and building
# - Component assembly and preview
# - Automation generation and testing
# - Web app/website/landing page creation
#
# It provides a high-level API for the Design Space UI and agents.
#
class DesignSpaceService
  attr_reader :user, :entity, :session_id

  def initialize(user, entity, session_id = nil)
    @user = user
    @entity = entity
    @session_id = session_id || SecureRandom.uuid
  end

  # ============================================
  # APPLICATION BUILDING
  # ============================================

  # Start a new application design session
  def start_design_session(name:, description:, type: 'module')
    plan = ApplicationPlannerService.new(@user, @entity).create_plan(
      name: name,
      description: description,
      type: type
    )

    broadcast_to_canvas('application_plan_preview', plan_preview_data(plan))

    {
      success: true,
      plan_id: plan.id,
      plan: plan_preview_data(plan),
      message: "I've created a design plan for '#{name}'. Review it in the canvas."
    }
  end

  # Update an existing plan
  def update_design_plan(plan_id:, updates:)
    plan = ApplicationPlan.find_by(id: plan_id, entity: @entity)
    return { success: false, message: "Plan not found" } unless plan

    updated_plan = ApplicationPlannerService.new(@user, @entity, plan).refine_plan(
      name: updates[:name],
      description: updates[:description],
      type: updates[:type],
      initial_requirements: updates[:requirements]
    )

    broadcast_to_canvas('application_plan_preview', plan_preview_data(updated_plan))

    {
      success: true,
      plan_id: updated_plan.id,
      plan: plan_preview_data(updated_plan),
      message: "Plan updated. Review the changes in the canvas."
    }
  end

  # Approve and build a plan
  def build_approved_plan(plan_id:)
    plan = ApplicationPlan.find_by(id: plan_id, entity: @entity)
    return { success: false, message: "Plan not found" } unless plan

    plan.approve! unless plan.approved?

    result = ApplicationBuildService.new(plan).execute!

    if result[:success]
      # Show the newly built app in preview
      if plan.web_app_plan.present?
        web_app = WebApp.find_by(entity: @entity, slug: plan.web_app_plan['slug'])
        broadcast_preview('web_app', web_app.id, web_app.name) if web_app
      elsif plan.website_plan.present?
        website = Website.find_by(entity: @entity, name: plan.website_plan['name'])
        broadcast_preview('website', website.id, website.name) if website
      elsif plan.modules_plan.any?
        app_module = AppModule.find_by(entity: @entity, slug: plan.modules_plan.first['slug'])
        broadcast_preview('module', app_module.slug, app_module.name) if app_module
      end
    end

    result
  end

  # ============================================
  # COMPONENT MANAGEMENT
  # ============================================

  # Get component recommendations for a section type
  def get_component_recommendations(section_type:, business_type: nil)
    library = Agents::FrontendDesignExpert::COMPONENT_LIBRARY
    section = library[section_type.to_sym]
    
    return { success: false, message: "Unknown section type: #{section_type}" } unless section

    # Get design system recommendations if business type provided
    design_systems = if business_type.present?
      Agents::FrontendDesignExpert.recommend_design_system(business_type: business_type)
    else
      [Agents::FrontendDesignExpert::DESIGN_SYSTEMS[:modern].merge(key: :modern)]
    end

    {
      success: true,
      section_type: section_type,
      variants: section[:variants],
      recommended_design_systems: design_systems
    }
  end

  # Generate component HTML with data
  def generate_component(type:, variant:, data: {}, design_system: :modern)
    template_path = Rails.root.join(
      'app', 'views', 'components', 'bootstrap',
      type.to_s, "_#{variant}.html.erb"
    )

    unless File.exist?(template_path)
      return { success: false, message: "Component template not found: #{type}/#{variant}" }
    end

    # Generate CSS variables for the design system
    css_variables = Agents::FrontendDesignExpert.generate_css_variables(design_system)

    # Render the template with data
    html = ApplicationController.render(
      partial: "components/bootstrap/#{type}/#{variant}",
      locals: data.symbolize_keys
    )

    {
      success: true,
      html: html,
      css_variables: css_variables,
      design_system: design_system
    }
  rescue => e
    { success: false, message: "Failed to generate component: #{e.message}" }
  end

  # ============================================
  # AUTOMATION MANAGEMENT
  # ============================================

  # Create an automation from natural language
  def create_automation(name:, description:, trigger_type:, trigger_config: {}, module_slug: nil)
    app_module = module_slug.present? ? AppModule.find_by(slug: module_slug, entity: @entity) : nil

    tool = GenerateAutomationCodeTool.new(@user, @entity, @session_id)
    result = tool.execute({
      'name' => name,
      'description' => description,
      'trigger_type' => trigger_type,
      'trigger_config' => trigger_config,
      'module_slug' => module_slug
    })

    if result[:success] && result[:automation_id]
      automation = AutomationCode.find(result[:automation_id])
      broadcast_to_canvas('workflow_designer', workflow_designer_data(automation))
    end

    result
  end

  # Test an automation
  def test_automation(automation_id:, test_data: {})
    automation = AutomationCode.find_by(id: automation_id, entity: @entity)
    return { success: false, message: "Automation not found" } unless automation

    result = AutomationCodeExecutor.new(automation).execute(test_data, dry_run: true)

    {
      success: result[:success],
      automation_id: automation.id,
      output: result[:data],
      error: result[:error],
      is_tested: automation.is_tested?
    }
  end

  # ============================================
  # PREVIEW MANAGEMENT
  # ============================================

  # Load a preview in the canvas
  def load_preview(type:, id_or_slug:, edit_mode: false)
    case type.to_sym
    when :web_app
      web_app = WebApp.find_by(id: id_or_slug, entity: @entity)
      return { success: false, message: "Web app not found" } unless web_app
      
      broadcast_preview('web_app', web_app.id, web_app.name, edit_mode: edit_mode)
    when :website
      website = Website.find_by(id: id_or_slug, entity: @entity)
      return { success: false, message: "Website not found" } unless website
      
      broadcast_preview('website', website.id, website.name, edit_mode: edit_mode)
    when :landing_page
      lp = LandingPage.find_by(id: id_or_slug, entity: @entity)
      return { success: false, message: "Landing page not found" } unless lp
      
      broadcast_preview('landing_page', lp.id, lp.title, edit_mode: edit_mode)
    when :module
      app_module = AppModule.find_by(slug: id_or_slug, entity: @entity)
      return { success: false, message: "Module not found" } unless app_module
      
      broadcast_preview('module', app_module.slug, app_module.name, edit_mode: edit_mode)
    when :automation
      automation = AutomationCode.find_by(id: id_or_slug, entity: @entity)
      return { success: false, message: "Automation not found" } unless automation
      
      broadcast_to_canvas('workflow_designer', workflow_designer_data(automation))
    else
      return { success: false, message: "Unknown preview type: #{type}" }
    end

    { success: true, type: type, id: id_or_slug }
  end

  # ============================================
  # QUICK ACTIONS
  # ============================================

  # Quick-create a landing page
  def quick_create_landing_page(title:, description:, style: :modern)
    # Use the existing landing page generator
    tool = GenerateLandingPageTool.new(@user, @entity, @session_id)
    result = tool.execute({
      'title' => title,
      'company_description' => description,
      'style' => style.to_s
    })

    if result[:success] && result[:landing_page_id]
      broadcast_preview('landing_page', result[:landing_page_id], title, edit_mode: true)
    end

    result
  end

  # Quick-create a module
  def quick_create_module(name:, fields:)
    plan = ApplicationPlannerService.new(@user, @entity).create_plan(
      name: name,
      description: "Custom module: #{name}",
      type: 'module',
      initial_requirements: {
        modules: [{ name: name, slug: name.parameterize, fields: fields }]
      }
    )

    plan.approve!
    ApplicationBuildService.new(plan).execute!
  end

  private

  def broadcast_to_canvas(canvas_type, data)
    ActionCable.server.broadcast(
      "scout_canvas_#{@session_id}",
      { type: canvas_type, data: data }
    )
  rescue => e
    Rails.logger.error "[DesignSpaceService] Failed to broadcast: #{e.message}"
  end

  def broadcast_preview(preview_type, id, title, edit_mode: false)
    url = case preview_type
    when 'web_app' then "/design_preview/web_app/#{id}"
    when 'website' then "/design_preview/website/#{id}"
    when 'landing_page' then "/design_preview/landing_page/#{id}"
    when 'module' then "/design_preview/module/#{id}"
    else nil
    end

    broadcast_to_canvas('design_preview', {
      preview_type: preview_type,
      preview_url: url,
      title: title,
      edit_mode: edit_mode
    })
  end

  def plan_preview_data(plan)
    plan.as_json(
      only: [:id, :name, :description, :status, :plan_data],
      methods: [:modules_plan, :website_plan, :web_app_plan, :agent_plan, 
                :tools_plan, :integrations_plan, :workflows_plan, 
                :scheduled_tasks_plan, :hub_hooks_plan]
    )
  end

  def workflow_designer_data(automation)
    nodes = build_workflow_nodes(automation)
    {
      workflow_name: automation.name,
      workflow_id: automation.id,
      status: automation.status,
      nodes: nodes,
      edges: nodes.each_with_index.map { |n, i| i > 0 ? { from: nodes[i-1][:id], to: n[:id] } : nil }.compact
    }
  end

  def build_workflow_nodes(automation)
    nodes = [{
      id: 'trigger',
      type: 'trigger',
      label: "#{automation.trigger_type.titleize}: #{automation.trigger_config.to_json.truncate(50)}"
    }]

    code = automation.code || ''
    nodes << { id: 'slack', type: 'notification', label: 'Send Slack' } if code.include?('send_slack_message')
    nodes << { id: 'email', type: 'notification', label: 'Send Email' } if code.include?('send_email')
    nodes << { id: 'http', type: 'integration', label: 'HTTP Request' } if code.include?('http_')
    nodes << { id: 'update', type: 'action', label: 'Update Record' } if code.include?('update_record')
    nodes << { id: 'create', type: 'action', label: 'Create Record' } if code.include?('create_record')

    nodes
  end
end

