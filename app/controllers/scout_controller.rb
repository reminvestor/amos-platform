class ScoutController < ApplicationController
  include ActionController::Live  # Enable real-time streaming
  
  before_action :authenticate_user!
  before_action :ensure_entity_exists
  before_action :ensure_onboarded
  
  layout 'scout'
  
  def index
    @session_id = session[:scout_session_id] ||= SecureRandom.uuid
    @conversation_history = scout_conversation_history
    
    # If this is a fresh start, add Scout's welcome message
    if @conversation_history.empty?
      create_welcome_message
      @conversation_history = scout_conversation_history
    end
    
    # Business context for display
    @business_profile = current_user.business_profile
    @entity = current_entity
  end
  
  def chat
    @session_id = session[:scout_session_id] ||= SecureRandom.uuid
    user_message = params[:message]&.strip
    
    Rails.logger.info "Scout chat - Session: #{@session_id}, User: #{current_user.id}, Message: #{user_message}"
    
    if user_message.blank?
      render json: { error: 'Message cannot be empty' }, status: 400
      return
    end
    
    begin
      # Save user message
      save_scout_message('user', user_message)
      Rails.logger.info "Scout: Saved user message"
      
      # Use the new generic tools service
      generic_tools_service = ScoutGenericToolsService.new(current_user, current_entity)
      conversation_history = scout_conversation_history
      response = generic_tools_service.process_message_with_tools(user_message, conversation_history)
      
      Rails.logger.info "Scout: Got response - tools_used: #{response[:tools_used]}, success_count: #{response[:success_count]}"
      
      # Save Scout's response
      save_scout_message('assistant', response[:message])
      
      # Return structured response
      render json: {
        message: response[:message],
        tools_used: response[:tools_used],
        tools_list: response[:tools_list],
        success_count: response[:success_count],
        error_count: response[:error_count],
        canvas: response[:canvas]
      }
      
    rescue StandardError => e
      Rails.logger.error "Scout chat error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Fallback response
      fallback_message = "I apologize, but I'm experiencing some technical difficulties. Please try again, or contact support if the issue persists."
      save_scout_message('assistant', fallback_message)
      
      render json: { 
        message: fallback_message,
        error: true,
        tools_used: false
      }, status: 500
    end
  end

  def chat_stream
    @session_id = session[:scout_session_id] ||= SecureRandom.uuid
    user_message = params[:message]&.strip
    
    Rails.logger.info "Scout streaming chat - Session: #{@session_id}, User: #{current_user.id}, Message: #{user_message}"
    
    if user_message.blank?
      render json: { error: 'Message cannot be empty' }, status: 400
      return
    end

    # Set streaming headers
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Connection'] = 'keep-alive'
    response.headers['X-Accel-Buffering'] = 'no' # Prevent nginx buffering
    response.headers['Access-Control-Allow-Origin'] = '*'
    
    # Force the headers to be sent immediately
    response.status = 200
    
    begin
      # Send immediate response to establish streaming
      stream_update("💬 Message received")
      
      # Save user message
      save_scout_message('user', user_message)
      stream_update("📚 Loading conversation history...")
      
      # Get conversation history
      conversation_history = scout_conversation_history
      stream_update("📚 Loading conversation history (#{conversation_history.length} messages)")
      
      # Use generic tools service with streaming updates
      stream_update("🧠 Analyzing your request...")
      generic_tools_service = ScoutGenericToolsService.new(current_user, current_entity)
      
      # Process message with streaming progress updates
      final_response = generic_tools_service.process_message_with_tools_streaming(
        user_message, 
        ->(message) { stream_update(message) },  # Pass streaming callback
        conversation_history  # Pass conversation history
      )
      
      # Save Scout's response
      save_scout_message('assistant', final_response[:message])
      
      # Send final response
      stream_update("✅ Complete")
      stream_final_response(final_response)
      
    rescue StandardError => e
      Rails.logger.error "Scout streaming chat error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Fallback response
      fallback_message = "I apologize, but I'm experiencing some technical difficulties. Please try again, or contact support if the issue persists."
      save_scout_message('assistant', fallback_message)
      
      stream_update("❌ Error occurred")
      stream_final_response({
        message: fallback_message,
        error: true,
        tools_used: false
      })
    ensure
      response.stream.close
    end
  end
  
  # Template/Canvas Actions for Intelligent Canvas
  def load_canvas
    canvas_type = params[:canvas_type]
    canvas_data = params[:canvas_data] || {}
    
    begin
      Rails.logger.info "Scout: Loading canvas - Type: #{canvas_type}, Data: #{canvas_data}"
      
      case canvas_type
      when 'landing_page_viewer'
        canvas_content = render_landing_page_canvas(canvas_data)
        canvas_title = "Landing Page Viewer"
      when 'landing_page_generator' 
        canvas_content = render_landing_page_generator(canvas_data)
        canvas_title = "Landing Page Generator"
      when 'contact_viewer'
        canvas_content = render_contact_canvas(canvas_data)
        canvas_title = "Contacts"
      when 'campaign_viewer'
        canvas_content = render_campaign_canvas(canvas_data)
        canvas_title = "Campaigns"
      when 'analytics_dashboard'
        canvas_content = render_analytics_canvas(canvas_data)
        canvas_title = "Analytics Dashboard"
      when 'contact_generator'
        canvas_content = render_contact_generator(canvas_data)
        canvas_title = "Create Contact"
      else
        canvas_content = render_default_canvas
        canvas_title = "Scout Canvas"
      end
      
      render json: {
        success: true,
        canvas: {
          type: canvas_type,
          title: canvas_title,
          content: canvas_content,
          data: canvas_data
        }
      }
    rescue => e
      Rails.logger.error "Canvas loading error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      render json: {
        success: false,
        error: "Sorry, I couldn't load that view."
      }
    end
  end

  def available_canvases
    begin
      # Return available canvas types for Scout
      canvases = [
        { 
          type: 'landing_page_viewer', 
          name: 'Landing Pages', 
          description: 'View and manage landing pages',
          icon: 'fas fa-globe'
        },
        { 
          type: 'contact_viewer', 
          name: 'Contacts', 
          description: 'View and manage contacts',
          icon: 'fas fa-users'
        },
        { 
          type: 'campaign_viewer', 
          name: 'Campaigns', 
          description: 'View and manage email campaigns',
          icon: 'fas fa-envelope'
        },
        { 
          type: 'analytics_dashboard', 
          name: 'Analytics', 
          description: 'Marketing performance dashboard',
          icon: 'fas fa-chart-bar'
        }
      ]
      
      # Add data-specific canvases if we have recent data
      if current_entity.landing_pages.recent.limit(1).exists?
        recent_page = current_entity.landing_pages.recent.first
        canvases << {
          type: 'landing_page_generator',
          name: recent_page.title || "Recent Landing Page",
          description: 'Landing page in progress',
          icon: 'fas fa-edit',
          data: { landing_page_id: recent_page.id }
        }
      end
      
      render json: { canvases: canvases }
    rescue => e
      Rails.logger.error "Available canvases error: #{e.message}"
      render json: { canvases: [] }
    end
  end
  
  def clear_conversation
    session_id = session[:scout_session_id]
    if session_id
      Rails.cache.delete("scout_conversation_#{session_id}")
      session.delete(:scout_session_id)
    end
    
    render json: { success: true, message: "Conversation cleared" }
  end
  
  def conversation_export
    @session_id = session[:scout_session_id]
    @conversation_history = scout_conversation_history
    
    respond_to do |format|
      format.json { render json: @conversation_history }
      format.html # Will render conversation_export.html.erb if you create one
    end
  end
  
  private

  def stream_update(message)
    # Create the SSE (Server-Sent Events) format
    data = JSON.generate({ type: 'update', message: message })
    chunk = "data: #{data}\n\n"
    
    # Write and try to force immediate sending
    response.stream.write(chunk)
    
    # Try multiple methods to flush
    begin
      response.stream.flush if response.stream.respond_to?(:flush)
    rescue
      # Ignore flush errors
    end
    
    # Force Rails to send the response chunk immediately
    begin
      if defined?(ActionController::Live) && response.stream.is_a?(ActionController::Live::SSE)
        response.stream.instance_variable_get(:@stream).flush rescue nil
      end
    rescue
      # Ignore if this doesn't work
    end
    
    Rails.logger.info "Streamed update: #{message[0..50]}..."
    
  rescue => e
    Rails.logger.error "Stream update error: #{e.message}"
  end

  def stream_final_response(response_data)
    # Create the final SSE response
    data = JSON.generate({ type: 'response', data: response_data })
    chunk = "data: #{data}\n\n"
    
    # Write and try to force immediate sending
    response.stream.write(chunk)
    
    # Try to flush
    begin
      response.stream.flush if response.stream.respond_to?(:flush)
    rescue
      # Ignore flush errors
    end
    
    Rails.logger.info "Streamed final response"
    
  rescue => e
    Rails.logger.error "Stream final response error: #{e.message}"
  end
  
  def current_entity
    @current_entity ||= begin
      # First check if entity is set in session
      if session[:entity_id]
        current_user.entities.find_by(id: session[:entity_id])
      else
        # If no entity in session but user has exactly one entity, auto-set it
        if current_user.entities.count == 1
          entity = current_user.entities.first
          session[:entity_id] = entity.id
          Rails.logger.info "🔧 Auto-set entity for user #{current_user.id}: #{entity.name} (ID: #{entity.id})"
          entity
        else
          # User has no entities or multiple entities - let them choose
          current_user.entity_users.first&.entity
        end
      end
    end
  end
  
  def ensure_entity_exists
    unless current_entity
      redirect_to new_entity_path, alert: "You need to set up your business profile first."
    end
  end
  
  def ensure_onboarded
    unless current_user.onboarded?
      redirect_to onboarding_path, notice: "Let's finish setting up your profile first."
    end
  end
  
  def scout_conversation_history
    session_id = session[:scout_session_id]
    return [] unless session_id
    
    Rails.cache.fetch("scout_conversation_#{session_id}", expires_in: 2.hours) || []
  end
  
  def save_scout_message(role, message)
    session_id = session[:scout_session_id]
    return unless session_id
    
    conversation = scout_conversation_history
    conversation << {
      role: role,
      content: message,
      timestamp: Time.current.iso8601,
      session_id: session_id
    }
    
    # Keep conversation manageable (last 50 messages)
    conversation = conversation.last(50) if conversation.length > 50
    
    Rails.cache.write("scout_conversation_#{session_id}", conversation, expires_in: 2.hours)
  end
  
  def create_welcome_message
    business_name = current_entity&.name || "your business"
    profile = current_user.business_profile
    
    welcome_message = if profile&.industry.present?
      "Welcome back! I'm Scout, your AI marketing assistant for #{business_name}. " \
      "I can help you analyze your #{profile.industry.downcase} marketing performance, " \
      "optimize campaigns, manage contacts, and create new marketing materials. " \
      "What would you like to explore today? 🎯"
    else
      "Welcome to Scout! I'm your AI marketing assistant for #{business_name}. " \
      "I can help analyze your marketing performance, optimize campaigns, manage contacts, " \
      "and create new materials. What can I help you with today? 🚀"
    end
    
    save_scout_message('assistant', welcome_message)
  end

  # Canvas rendering methods
  def render_landing_page_canvas(data = {})
    landing_pages = current_entity.landing_pages.recent.limit(20)
    
    render_to_string(
      partial: 'scout/canvas/landing_page_viewer',
      locals: { 
        landing_pages: landing_pages,
        entity: current_entity,
        user: current_user,
        canvas_data: data
      }
    )
  end

  def render_landing_page_generator(data = {})
    landing_page = if data['landing_page_id']
      current_entity.landing_pages.find(data['landing_page_id'])
    else
      current_entity.landing_pages.build
    end
    
    # Get available form templates for the generator
    form_templates = LandingPageFormTemplatesService.available_templates
    
    render_to_string(
      partial: 'scout/canvas/landing_page_generator', 
      locals: { 
        landing_page: landing_page,
        form_templates: form_templates,
        entity: current_entity,
        user: current_user,
        canvas_data: data
      }
    )
  end

  def render_contact_canvas(data = {})
    contacts = current_entity.contacts.includes(:contact_groups).recent.limit(50)
    
    # Get summary stats
    stats = {
      total_contacts: current_entity.contacts.count,
      recent_contacts: current_entity.contacts.where('created_at > ?', 7.days.ago).count,
      contact_groups: current_entity.contact_groups.count
    }
    
    render_to_string(
      partial: 'scout/canvas/contact_viewer',
      locals: { 
        contacts: contacts,
        stats: stats,
        entity: current_entity,
        user: current_user,
        canvas_data: data
      }
    )
  end

  def render_contact_generator(data = {})
    contact = current_entity.contacts.build
    contact_groups = current_entity.contact_groups.limit(20)
    
    render_to_string(
      partial: 'scout/canvas/contact_generator',
      locals: { 
        contact: contact,
        contact_groups: contact_groups,
        entity: current_entity,
        user: current_user,
        canvas_data: data
      }
    )
  end

  def render_campaign_canvas(data = {})
    campaigns = current_entity.campaigns.includes(:email_deliveries, :contact_group).recent.limit(20)
    
    # Get summary stats
    stats = {
      total_campaigns: current_entity.campaigns.count,
      sent_campaigns: current_entity.campaigns.where(status: 'sent').count,
      draft_campaigns: current_entity.campaigns.where(status: 'draft').count
    }
    
    render_to_string(
      partial: 'scout/canvas/campaign_viewer',
      locals: { 
        campaigns: campaigns,
        stats: stats,
        entity: current_entity,
        user: current_user,
        canvas_data: data
      }
    )
  end

  def render_analytics_canvas(data = {})
    # Get analytics data for the dashboard
    analytics_data = {
      campaigns: current_entity.campaigns.includes(:email_deliveries).limit(10),
      recent_contacts: current_entity.contacts.where('created_at > ?', 30.days.ago).count,
      total_emails_sent: current_entity.campaigns.sum { |c| c.mailgun_stats&.dig('sent') || 0 },
      avg_open_rate: calculate_avg_open_rate,
      landing_pages: current_entity.landing_pages.count
    }
    
    render_to_string(
      partial: 'scout/canvas/analytics_dashboard',
      locals: { 
        analytics_data: analytics_data,
        entity: current_entity,
        user: current_user,
        canvas_data: data
      }
    )
  end

  def render_default_canvas
    render_to_string(
      partial: 'scout/canvas/default',
      locals: { 
        entity: current_entity,
        user: current_user
      }
    )
  end

  def calculate_avg_open_rate
    campaigns_with_stats = current_entity.campaigns.where.not(mailgun_stats: nil)
    return 0 if campaigns_with_stats.empty?
    
    total_sent = 0
    total_opened = 0
    
    campaigns_with_stats.each do |campaign|
      sent = campaign.mailgun_stats&.dig('sent') || 0
      opened = campaign.mailgun_stats&.dig('opened') || 0
      total_sent += sent
      total_opened += opened
    end
    
    return 0 if total_sent == 0
    ((total_opened.to_f / total_sent) * 100).round(1)
  end
end 