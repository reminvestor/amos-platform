class WorkspaceController < ApplicationController
  before_action :authenticate_user!
  layout 'workspace'
  
  require 'securerandom'
  
  # Load Scout AI services
  require_relative '../services/scout_ai/conversation_service'
  require_relative '../services/scout_ai/conversation_engine'
  require_relative '../services/scout_ai/intent_analyzer'
  require_relative '../services/scout_ai/business_extractor'
  require_relative '../jobs/process_background_intelligence_job'

  def index
    # Main workspace view
  end

  def chat
    message = params[:message]
    session_id = session[:scout_session_id] ||= SecureRandom.uuid
    
    begin
      # Use Scout AI conversation service
      scout_ai = ScoutAI::ConversationService.new(
        user: current_user,
        entity: current_entity,
        session_id: session_id
      )
      
      response = scout_ai.process_message(message)
      
      render json: response
    rescue => e
      Rails.logger.error "Scout AI Chat error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      render json: {
        success: false,
        response: "I apologize, but I'm having trouble processing your message right now. Please try again.",
        action: nil,
        payload: nil,
        session_id: session_id
      }
    end
  end

  def load_template
    template_id = params[:template_id]
    
    begin
      # For now, we'll use existing models as templates
      # This will be expanded as we build the template system
      
      case template_id
      when 'landing_page'
        template_content = render_landing_page_template
        template_name = "Landing Page Builder"
      when 'campaign'
        template_content = render_campaign_template
        template_name = "Email Campaign Builder"
      when 'analytics'
        template_content = render_analytics_template
        template_name = "Analytics Dashboard"
      else
        # Try to load from existing models
        template_content = load_existing_template(template_id)
        template_name = "Template"
      end
      
      render json: {
        success: true,
        template: {
          id: template_id,
          name: template_name,
          content: template_content
        }
      }
    rescue => e
      Rails.logger.error "Template loading error: #{e.message}"
      render json: {
        success: false,
        error: "Sorry, I couldn't load that template."
      }
    end
  end

  def templates
    begin
      # Return available templates for the sidebar
      templates = [
        { id: 'landing_page', name: 'Landing Pages', type: 'builder' },
        { id: 'campaign', name: 'Email Campaigns', type: 'builder' },
        { id: 'analytics', name: 'Analytics', type: 'dashboard' }
      ]
      
      # Add user's actual templates
      if current_user && current_entity.present?
        # Landing pages
        current_user.landing_pages.where(entity_id: current_entity.id).limit(5).each do |page|
          templates << {
            id: "landing_page_#{page.id}",
            name: page.title.presence || "Landing Page #{page.id}",
            type: 'landing_page'
          }
        end
        
        # Campaigns
        current_user.campaigns.where(entity_id: current_entity.id).limit(5).each do |campaign|
          templates << {
            id: "campaign_#{campaign.id}",
            name: campaign.name.presence || "Campaign #{campaign.id}",
            type: 'campaign'
          }
        end
      end
      
      render json: { templates: templates }
    rescue => e
      Rails.logger.error "Templates error: #{e.message}"
      Rails.logger.error e.backtrace
      render json: { templates: [
        { id: 'landing_page', name: 'Landing Pages', type: 'builder' },
        { id: 'campaign', name: 'Email Campaigns', type: 'builder' },
        { id: 'analytics', name: 'Analytics', type: 'dashboard' }
      ] }
    end
  end

  private



  def render_landing_page_template
    # Render landing page management interface
    render_to_string(
      partial: 'workspace/templates/landing_page',
      locals: { 
        landing_pages: current_user.landing_pages.where(entity_id: current_entity.id).limit(10),
        user: current_user
      }
    )
  end

  def render_campaign_template
    # Render campaign management interface
    render_to_string(
      partial: 'workspace/templates/campaign',
      locals: { 
        campaigns: current_user.campaigns.where(entity_id: current_entity.id).limit(10),
        user: current_user
      }
    )
  end

  def render_analytics_template
    # Render analytics dashboard
    render_to_string(
      partial: 'workspace/templates/analytics',
      locals: { 
        entity: current_entity,
        user: current_user
      }
    )
  end

  def load_existing_template(template_id)
    # Handle loading specific templates by ID
    if template_id.start_with?('landing_page_')
      page_id = template_id.split('_').last
      page = current_user.landing_pages.where(entity_id: current_entity.id).find(page_id)
      return render_to_string(
        partial: 'workspace/templates/landing_page_editor',
        locals: { landing_page: page }
      )
    elsif template_id.start_with?('campaign_')
      campaign_id = template_id.split('_').last
      campaign = current_user.campaigns.where(entity_id: current_entity.id).find(campaign_id)
      return render_to_string(
        partial: 'workspace/templates/campaign_editor',
        locals: { campaign: campaign }
      )
    end
    
    # Default fallback
    "<div class='alert alert-info'>Template not found</div>"
  end
end
