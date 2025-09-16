class ScoutController < ApplicationController
  include ActionController::Live  # Enable real-time streaming
  
  before_action :authenticate_user!
  before_action :ensure_entity_exists
  before_action :ensure_onboarded
  
  layout 'scout'
  
  def index
    @session_id = session[:scout_session_id] ||= SecureRandom.uuid
    @conversation_history = persisted_history_last_k(10)
    
    # If this is a fresh start, add Scout's welcome message
    if @conversation_history.empty?
      create_welcome_message
      @conversation_history = persisted_history_last_k(10)
    end
    
    # Business context for display
    @business_profile = current_user.business_profile
    @entity = current_entity
  end
  
  def chat
    @session_id = session[:scout_session_id] ||= SecureRandom.uuid
    user_message = params[:message]&.strip
    current_canvas = params[:current_canvas]
    
    Rails.logger.info "Scout chat - Session: #{@session_id}, User: #{current_user.id}, Message: #{user_message}"
    Rails.logger.info "Current canvas context: #{current_canvas.inspect}" if current_canvas
    
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
      conversation_history = persisted_history_last_k(12)
      response = generic_tools_service.process_message_with_tools(user_message, conversation_history, current_canvas)
      
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
    current_canvas = params[:current_canvas]
    
    Rails.logger.info "Scout streaming chat - Session: #{@session_id}, User: #{current_user.id}, Message: #{user_message}"
    puts "🚨 PRODUCTION DEBUG: Scout chat request received - #{Time.current}"
    STDOUT.flush
    Rails.logger.info "Current canvas context: #{current_canvas.inspect}" if current_canvas
    
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
    puts "🚨 PRODUCTION DEBUG: SSE Headers set - #{Time.current}"
    STDOUT.flush
    
    # Force the headers to be sent immediately
    response.status = 200
    
    begin
      # Send immediate response to establish streaming
      stream_update("💬 Message received")
      
      # Save user message
      save_scout_message('user', user_message)
      stream_update("📚 Loading conversation history...")
      
      # Get conversation history
      conversation_history = persisted_history_last_k(12)
      stream_update("📚 Loading conversation history (#{conversation_history.length} messages)")
      
      # Use generic tools service with streaming updates
      stream_update("🧠 Analyzing your request...")
      stream_update("📋 Preparing context and tools...")
      generic_tools_service = ScoutGenericToolsService.new(current_user, current_entity)
      
      # Process message with streaming progress updates
      final_response = generic_tools_service.process_message_with_tools_streaming(
        user_message, 
        ->(message) { stream_update(message) },  # Pass streaming callback (multi-line supported below)
        conversation_history,  # Pass conversation history
        current_canvas  # Pass current canvas context
      )
      
      # Save Scout's response
      save_scout_message('assistant', final_response[:message])
      
      # Send completion indicator
      stream_update("✅ Complete")
      
      # Send job started status if there's an active job
      send_job_started_status_if_exists(final_response)
      
      # Stream the Claude response as an intermediate update
      if final_response[:message].present?
        stream_update("💬 #{final_response[:message]}")
      end
      
      # Always send final response immediately - let job run in background
      stream_final_response(final_response)
      
      # Optional: Log that background job is running
      if final_response[:canvas_data]&.dig(:landing_page_id)
        Rails.logger.info "🚀 Background job processing, user can refresh to see updates"
      end
      
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
      when 'landing_page_details'
        canvas_content = render_landing_page_details(canvas_data)
        canvas_title = "Landing Page Details"
      when 'landing_page_generator' 
        canvas_content = render_landing_page_generator(canvas_data)
        canvas_title = "Landing Page Generator"
      when 'landing_page_editor'
        canvas_content = render_landing_page_editor(canvas_data)
        canvas_title = "Edit Landing Page"
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
      when 'user_profile'
        canvas_content = render_user_profile_canvas(canvas_data)
        canvas_title = "My Profile"
      when 'business_profile'
        canvas_content = render_business_profile_canvas(canvas_data)
        canvas_title = "Business Settings"
      when 'email_template_viewer'
        canvas_content = render_email_template_viewer(canvas_data)
        canvas_title = "Email Templates"
      when 'email_template_editor'
        canvas_content = render_email_template_editor(canvas_data)
        canvas_title = "Edit Email Template"
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
      Rails.logger.error "Canvas loading error: #{e.class.name}: #{e.message}"
      Rails.logger.error "Canvas type: #{canvas_type}, Data: #{canvas_data}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      
      render json: {
        success: false,
        error: "Sorry, I couldn't load that view. Error: #{e.message}"
      }, status: :ok
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

  # GET /scout/history?before_id=<id>&limit=20
  def history
    session_id = session[:scout_session_id]
    limit = params[:limit].to_i
    limit = 20 if limit <= 0 || limit > 100
    before_id = params[:before_id]

    scope = ScoutMessage.for_session(session_id).oldest_first
    if before_id.present?
      # Load messages older than the given id
      before_message = ScoutMessage.find_by(id: before_id)
      scope = scope.where('created_at < ?', before_message.created_at) if before_message
    end

    batch = scope.last(limit)
    render json: {
      messages: batch.map { |m| { id: m.id, role: m.role, content: m.content, timestamp: m.created_at.iso8601 } },
      has_more: ScoutMessage.for_session(session_id).count > (before_id.present? ? ScoutMessage.for_session(session_id).where('created_at <= ?', batch.first&.created_at).count : batch.count)
    }
  end

  def stream_update(message)
    puts "🚨 PRODUCTION DEBUG: Streaming update: #{message}"
    STDOUT.flush
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
    
    Rails.logger.info "Streamed update: #{message.to_s.lines.first&.strip.to_s[0..80]}..."
    
  rescue => e
    Rails.logger.error "Stream update error: #{e.message}"
  end

  def stream_final_response(response_data)
    Rails.logger.info "🌊 stream_final_response called with data keys: #{response_data.keys}"
    Rails.logger.info "📝 Message content: #{response_data[:message]}"
    
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
  
  def check_active_job_status(response_data)
    Rails.logger.info "🔍 Checking active job status for response data: #{response_data.keys}"
    
    # Only check for job status if the response includes canvas data with landing_page_id
    unless response_data[:canvas_data]&.dig(:landing_page_id)
      Rails.logger.info "❌ No canvas_data or landing_page_id found"
      return nil
    end
    
    landing_page_id = response_data[:canvas_data][:landing_page_id]
    job_status_key = "job_status_#{current_user.id}_#{landing_page_id}"
    
    Rails.logger.info "🔍 Looking for job status with key: #{job_status_key}"
    
    # Get job status from cache
    job_status = Rails.cache.read(job_status_key)
    
    if job_status
      Rails.logger.info "📊 Found job status for LP #{landing_page_id}: #{job_status[:type]} (#{job_status[:status]})"
      
      # Don't clear processing status, only clear completed/failed status
      if job_status[:status].in?(['completed', 'failed'])
        Rails.cache.delete(job_status_key)
        Rails.logger.info "🗑️ Cleared consumed job status from cache"
      else
        Rails.logger.info "⏳ Keeping processing job status in cache for future checks"
      end
      
      return job_status
    else
      Rails.logger.info "❌ No job status found in cache for key: #{job_status_key}"
    end
    
    nil
  end

  def send_job_started_status_if_exists(response_data)
    # Only check if there's a landing page job 
    return unless response_data[:canvas_data]&.dig(:landing_page_id)
    
    landing_page_id = response_data[:canvas_data][:landing_page_id]
    job_status_key = "job_status_#{current_user.id}_#{landing_page_id}"
    
    # Get job status from cache
    job_status = Rails.cache.read(job_status_key)
    
    if job_status && job_status[:status] == 'processing'
      Rails.logger.info "📡 Sending job_started status via SSE: #{job_status[:type]}"
      
      # Send job status through SSE
      job_data = JSON.generate({ type: 'job_status', data: job_status })
      job_chunk = "data: #{job_data}\n\n"
      response.stream.write(job_chunk)
      response.stream.flush if response.stream.respond_to?(:flush)
    else
      Rails.logger.info "❌ No processing job status found to send"
    end
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

  # DB-backed persistent history, paged
  def persisted_history_last_k(k = 10)
    session_id = session[:scout_session_id]
    return [] unless session_id
    ScoutMessage.for_session(session_id).oldest_first.last(k).map do |m|
      { role: m.role, content: m.content, timestamp: m.created_at.iso8601 }
    end
  end
  
  def save_scout_message(role, message)
    session_id = session[:scout_session_id]
    return unless session_id
    
    # Persist in DB (durable)
    ScoutMessage.create!(
      user_id: current_user.id,
      entity_id: current_entity&.id,
      session_id: session_id,
      role: role,
      content: message
    )
    
    # Mirror the last 50 in cache for fast UI render
    conversation = persisted_history_last_k(50)
    Rails.cache.write("scout_conversation_#{session_id}", conversation, expires_in: 12.hours)
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

  def render_landing_page_details(data = {})
    landing_page_id = data['landing_page_id'] || data[:landing_page_id]
    
    if landing_page_id.present?
      begin
        landing_page = current_entity.landing_pages.find(landing_page_id)
      rescue ActiveRecord::RecordNotFound
        # Fallback to most recent landing page if ID not found
        landing_page = current_entity.landing_pages.recent.first
      end
    else
      # Fallback to most recent landing page if no ID provided
      landing_page = current_entity.landing_pages.recent.first
    end
    
    # If no landing pages exist, return a helpful message
    if landing_page.nil?
      return render_to_string(
        inline: "<div class='text-center py-5'><h5>No Landing Pages Found</h5><p>Create your first landing page to get started.</p><button class='btn btn-primary' onclick='window.scoutCreateLandingPage()'>Create Landing Page</button></div>"
      )
    end
    
    render_to_string(
      partial: 'scout/canvas/landing_page_details',
      locals: { 
        landing_page: landing_page,
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

  def render_landing_page_editor(data = {})
    landing_page = current_entity.landing_pages.find(data['landing_page_id'])
    
    render_to_string(
      partial: 'scout/canvas/landing_page_editor',
      locals: { 
        landing_page: landing_page,
        entity: current_entity,
        user: current_user
      }
    )
  end

  def render_contact_canvas(data = {})
    contacts = current_entity.contacts.includes(:contact_groups).order(created_at: :desc).limit(50)
    
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
    # Load campaigns first with associations
    campaigns = current_entity.campaigns
      .includes(:contact_groups, :email_template)
      .recent
      .limit(20)
    
    # Get all delivery stats in one query
    campaign_ids = campaigns.pluck(:id)
    delivery_stats = EmailDelivery
      .where(campaign_id: campaign_ids)
      .group(:campaign_id)
      .pluck(
        :campaign_id,
        Arel.sql("COUNT(*) FILTER (WHERE sent_at IS NOT NULL)"),
        Arel.sql("COUNT(*) FILTER (WHERE opened_at IS NOT NULL)"),
        Arel.sql("COUNT(*) FILTER (WHERE clicked_at IS NOT NULL)"),
        Arel.sql("MIN(sent_at)")
      )
    
    # Build a hash for quick lookup
    stats_by_campaign = {}
    delivery_stats.each do |campaign_id, sent_count, opened_count, clicked_count, first_sent|
      stats_by_campaign[campaign_id] = {
        sent_count: sent_count,
        opened_count: opened_count,
        clicked_count: clicked_count,
        first_sent_at: first_sent
      }
    end
    
    # Inject stats into campaigns
    campaigns.each do |campaign|
      if stats = stats_by_campaign[campaign.id]
        campaign.instance_variable_set(:@cached_sent_count, stats[:sent_count])
        campaign.instance_variable_set(:@cached_opened_count, stats[:opened_count])
        campaign.instance_variable_set(:@cached_clicked_count, stats[:clicked_count])
        campaign.instance_variable_set(:@cached_first_sent_at, stats[:first_sent_at])
      end
    end
    
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

  def render_user_profile_canvas(data = {})
    render_to_string(
      partial: 'scout/canvas/user_profile',
      locals: { 
        user: current_user,
        entity: current_entity,
        canvas_data: data
      }
    )
  end

  def render_business_profile_canvas(data = {})
    render_to_string(
      partial: 'scout/canvas/business_profile',
      locals: {
        business_profile: current_user.business_profile,
        user: current_user,
        entity: current_entity,
        canvas_data: data
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

  def render_email_template_viewer(data = {})
    templates = current_entity.email_templates.order(created_at: :desc)
    
    # Get stats
    stats = {
      total_templates: templates.count,
      active_templates: templates.joins(:campaigns).distinct.count,
      used_templates: templates.joins(:campaigns).distinct.count,
      unused_templates: templates.left_joins(:campaigns).where(campaigns: { id: nil }).count
    }
    
    render_to_string(
      partial: 'scout/canvas/email_template_viewer',
      locals: {
        templates: templates,
        stats: stats,
        entity: current_entity,
        user: current_user,
        canvas_data: data
      }
    )
  end

  def render_email_template_editor(data = {})
    template_id = data['template_id'] || data[:template_id]
    email_template = current_entity.email_templates.find(template_id)
    
    render_to_string(
      partial: 'scout/canvas/email_template_editor',
      locals: {
        email_template: email_template,
        entity: current_entity,
        user: current_user,
        canvas_data: data
      }
    )
  end
end 