module Scout
  class CanvasRenderer
    def initialize(controller)
      @controller = controller
    end

    def render(canvas_type, data = {})
      case canvas_type
      when 'landing_page'
        render_landing_page_canvas(data)
      when 'landing_page_details'
        render_landing_page_details(data)
      when 'landing_page_editor'
        render_landing_page_editor(data)
      when 'contact'
        render_contact_canvas(data)
      when 'contact_generator'
        render_contact_generator(data)
      when 'campaign'
        render_campaign_canvas(data)
      when 'document_viewer'
        render_document_viewer_canvas(data)
      when 'analytics_dashboard'
        render_analytics_canvas(data)
      when 'default'
        render_default_canvas
      when 'user_profile'
        render_user_profile_canvas(data)
      when 'business_profile'
        render_business_profile_canvas(data)
      when 'email_template_viewer'
        render_email_template_viewer(data)
      when 'email_template_editor'
        render_email_template_editor(data)
      when 'dynamic_canvas'
        render_dynamic_canvas(data)
      when 'task_progress'
        render_task_progress(data)
      when 'form_submissions'
        render_form_submissions_canvas(data)
      when 'workflow_analytics'
        render_workflow_analytics_canvas(data)
      when 'integrations_manager'
        render_integrations_manager(data)
      when 'integration_connect'
        render_integration_connect(data)
      when 'integration_operations'
        render_integration_operations(data)
      when 'campaign_editor'
        render_campaign_editor(data)
      else
        render_default_canvas
      end
    end

    private

    attr_reader :controller

    delegate :current_entity, :current_user, :render_to_string, :number_to_human_size, to: :controller

    # This method will be populated with all canvas rendering methods from ScoutController
    # For now, keeping this as a placeholder - we'll move methods here in the next step
  end
end
