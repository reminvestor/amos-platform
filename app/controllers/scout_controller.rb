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
      generic_tools_service = ScoutGenericToolsService.new(current_user, current_entity, session[:scout_session_id])
      
      # Pass context to the service if available, or load from cache
      if context.present?
        generic_tools_service.set_context(context)
      else
        # Try to load existing context
        generic_tools_service.get_context
      end
      
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

  def chat_interactive
    @session_id = session[:scout_session_id] ||= SecureRandom.uuid
    user_message = params[:message]&.strip
    current_canvas = params[:current_canvas]
    context = params[:context]
    
    Rails.logger.info "Scout interactive chat - Session: #{@session_id}, User: #{current_user.id}, Message: #{user_message}"
    Rails.logger.info "Chat context: #{context.inspect}" if context
    
    if user_message.blank?
      render json: { error: 'Message cannot be empty' }, status: 400
      return
    end
    
    begin
      # Save user message
      save_scout_message('user', user_message)
      
      # Initialize interactive task service
      interactive_service = InteractiveTaskService.new(current_user, current_entity, @session_id)
      
      # Set up progress callback for real-time updates
      interactive_service.on_progress do |progress_data|
        # This could be used for WebSocket updates in the future
        Rails.logger.info "Workflow progress: #{progress_data.inspect}"
      end
      
      # Process the message
      result = interactive_service.process_message(user_message, persisted_history_last_k(12), current_canvas)
      
      # Save assistant response if present
      if result[:message]
        save_scout_message('assistant', result[:message])
      end
      
      # Return structured response
      render json: {
        success: result[:success],
        message: result[:message],
        canvas: result[:canvas],
        canvas_data: result[:canvas_data],
        mode: result[:mode],
        awaiting_input: result[:awaiting_input],
        workflow_completed: result[:workflow_completed],
        step_completed: result[:step_completed]
      }
      
    rescue => e
      Rails.logger.error "Scout interactive chat error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      render json: {
        success: false,
        message: "I encountered an error processing your request. Please try again.",
        error: e.message,
        canvas: 'conversation'
      }, status: 500
    end
  end
  
  def continue_workflow
    @session_id = session[:scout_session_id] ||= SecureRandom.uuid
    user_inputs = params[:inputs] || {}
    
    Rails.logger.info "Scout continue workflow - Session: #{@session_id}, Inputs: #{user_inputs.keys}"
    
    begin
      # Initialize interactive task service
      interactive_service = InteractiveTaskService.new(current_user, current_entity, @session_id)
      
      # Continue the workflow
      result = interactive_service.continue_workflow(user_inputs)
      
      # Save any assistant response
      if result[:message]
        save_scout_message('assistant', result[:message])
      end
      
      render json: {
        success: result[:success],
        message: result[:message],
        canvas: result[:canvas],
        canvas_data: result[:canvas_data],
        workflow_completed: result[:workflow_completed],
        step_completed: result[:step_completed]
      }
      
    rescue => e
      Rails.logger.error "Scout continue workflow error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      render json: {
        success: false,
        message: "I encountered an error continuing the workflow. Please try again.",
        error: e.message,
        canvas: 'conversation'
      }, status: 500
    end
  end

  def chat_stream
    @session_id = session[:scout_session_id] ||= SecureRandom.uuid
    user_message = params[:message]&.strip
    current_canvas = params[:current_canvas]
    context = params[:context]
    
    Rails.logger.info "Scout streaming chat - Session: #{@session_id}, User: #{current_user.id}, Message: #{user_message}"
    puts "🚨 PRODUCTION DEBUG: Scout chat request received - #{Time.current}"
    STDOUT.flush
    Rails.logger.info "Current canvas context: #{current_canvas.inspect}" if current_canvas
    Rails.logger.info "Chat context: #{context.inspect}" if context
    
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
      generic_tools_service = ScoutGenericToolsService.new(current_user, current_entity, session[:scout_session_id])
      
      # Pass context to the service if available, or load from cache
      if context.present?
        generic_tools_service.set_context(context)
      else
        # Try to load existing context
        generic_tools_service.get_context
      end
      
      # Track if we've started streaming content
      content_streaming = false
      
      # Process message with streaming progress updates
      final_response = generic_tools_service.process_message_with_tools_streaming(
        user_message, 
        ->(update) { 
          Rails.logger.info "🔄 Streaming callback received: #{update.inspect.first(100)}..."
          if update.is_a?(Hash)
            case update[:type]
            when 'content_chunk'
              # Stream content chunks directly to the user
              if !content_streaming
                content_streaming = true
                stream_update("💬 streaming")  # Signal start of content streaming
              end
              stream_content_chunk(update[:content])
            when 'save_message'
              # Save intermediate messages that occur before tool usage
              save_scout_message(update[:role] || 'assistant', update[:content], metadata: update[:metadata] || {})
              Rails.logger.info "💾 Saved intermediate message: #{update[:content]}"
              
              # Also stream the message to the UI immediately
              stream_update({
                type: 'intermediate_message',
                content: update[:content],
                role: update[:role] || 'assistant'
              })
            when 'load_canvas'
              # Immediately load a canvas (e.g., task progress)
              stream_update({
                type: 'load_canvas',
                canvas: update[:canvas],
                canvas_data: update[:canvas_data]
              })
              Rails.logger.info "🎨 Streaming canvas load: #{update[:canvas]}"
            when 'tool_detected', 'tool_start'
              # Save tool call as a message
              if update[:type] == 'tool_detected'
                save_scout_message('assistant', "tool:#{update[:name]}", metadata: {
                  type: 'tool_call',
                  tool_name: update[:name],
                  tool_id: update[:tool_id]
                })
                # Stream a message event to add the tool message to the UI
                stream_update({
                  type: 'add_tool_message',
                  tool_name: update[:name],
                  tool_id: update[:tool_id]
                })
              end
              # Stream tool events
              stream_update(update)
            else
              # Other hash updates
              stream_update(update) if update[:message]
            end
          elsif update.is_a?(String)
            stream_update(update)
          end
        },
        conversation_history,  # Pass conversation history
        current_canvas  # Pass current canvas context
      )
      
      # Save Scout's response only if it wasn't already saved during streaming
      if final_response[:message].present? && !final_response[:message_already_saved]
        Rails.logger.info "📨 Final response type: #{final_response[:message].class}"
        Rails.logger.info "📨 Final response content: #{final_response[:message].to_s.first(200)}..."
        save_scout_message('assistant', final_response[:message])
      else
        Rails.logger.info "📨 Final message already saved during streaming, skipping duplicate save"
      end
      
      # Send completion indicator
      stream_update("✅ Complete")
      
      # Load suggested canvas if available - but only if it hasn't been loaded during streaming
      # The task_progress canvas is loaded dynamically during task updates, so skip it here
      if final_response[:canvas] && final_response[:canvas] != 'conversation' && final_response[:canvas] != 'task_progress'
        Rails.logger.info "📋 Loading suggested canvas at end: #{final_response[:canvas]}"
        stream_update({
          type: 'load_canvas',
          canvas: final_response[:canvas],
          canvas_data: final_response[:canvas_data] || {}
        })
      elsif final_response[:canvas] == 'task_progress'
        Rails.logger.info "📋 Skipping task_progress canvas load at end - already loaded during streaming"
      end
      
      # Send job started status if there's an active job
      send_job_started_status_if_exists(final_response)
      
      # Don't stream the message as an update - it will be in the final response
      # This prevents duplicate messages
      # if final_response[:message].present?
      #   stream_update("💬 #{final_response[:message]}")
      # end
      
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
      when 'interactive_wizard'
        canvas_content = render_interactive_wizard(canvas_data)
        canvas_title = determine_wizard_title(canvas_data)
      when 'form_submissions'
        canvas_content = render_form_submissions_canvas(canvas_data)
        canvas_title = "Form Submissions"
      when 'workflow_analytics'
        canvas_content = render_workflow_analytics_canvas(canvas_data)
        canvas_title = "Workflow Analytics"
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
      when 'dynamic_canvas'
        canvas_content = render_dynamic_canvas(canvas_data)
        canvas_title = canvas_data['title'] || "Custom Analysis"
      when 'task_progress'
        canvas_content = render_task_progress(canvas_data)
        canvas_title = "Task Progress"
      when 'campaign_editor'
        canvas_content = render_campaign_editor(canvas_data)
        canvas_title = "Campaign Editor"
      when 'integrations_manager'
        canvas_content = render_integrations_manager(canvas_data)
        canvas_title = "Integration Connections"
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
          type: 'integrations_manager',
          name: 'Integrations',
          description: 'Manage external application connections',
          icon: 'fas fa-plug'
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
      messages: batch.map { |m| { 
        id: m.id, 
        role: m.role, 
        content: m.content, 
        timestamp: m.created_at.iso8601,
        metadata: m.metadata 
      } },
      has_more: ScoutMessage.for_session(session_id).count > (before_id.present? ? ScoutMessage.for_session(session_id).where('created_at <= ?', batch.first&.created_at).count : batch.count)
    }
  end

  # GET /scout/conversations
  def conversations
    # Get recent conversations for this user
    recent_sessions = ScoutMessage
      .where(user_id: current_user.id)
      .select(:session_id, 'MIN(created_at) as created_at', 'COUNT(*) as message_count')
      .group(:session_id)
      .order('MIN(created_at) DESC')
      .limit(10)
    
    # Get first message for each session
    conversations = recent_sessions.map do |session|
      first_message = ScoutMessage
        .where(session_id: session.session_id, role: 'user')
        .order(:created_at)
        .first
      
      {
        session_id: session.session_id,
        created_at: session.created_at,
        message_count: session.message_count,
        first_message: first_message&.content&.truncate(50)
      }
    end
    
    render json: conversations
  end
  
  # GET /scout/conversation/:session_id
  def conversation
    session_id = params[:session_id]
    messages = ScoutMessage
      .where(session_id: session_id, user_id: current_user.id)
      .order(:created_at)
      .map { |m| { 
        role: m.role, 
        content: m.content, 
        created_at: m.created_at.iso8601 
      } }
    
    render json: messages
  end
  
  # POST /scout/new_session
  def new_session
    # Clear old session cache if exists
    old_session_id = session[:scout_session_id]
    if old_session_id
      Rails.cache.delete("scout_conversation_#{old_session_id}")
    end
    
    # Create new session
    session[:scout_session_id] = SecureRandom.uuid
    render json: { session_id: session[:scout_session_id] }
  end
  
  private

  def stream_content_chunk(content)
    # Stream individual content chunks for real-time display
    puts "🚨 PRODUCTION DEBUG: Streaming content chunk: #{content}"
    STDOUT.flush
    
    data = JSON.generate({ type: 'content', content: content })
    chunk = "data: #{data}\n\n"
    
    response.stream.write(chunk)
    
    # Try to flush
    begin
      response.stream.flush if response.stream.respond_to?(:flush)
    rescue
      # Ignore flush errors
    end
    
    puts "✅ Content chunk streamed successfully"
    STDOUT.flush
  rescue => e
    Rails.logger.error "Stream content chunk error: #{e.message}"
    puts "❌ Stream content chunk error: #{e.message}"
    STDOUT.flush
  end

  def stream_update(message)
    puts "🚨 PRODUCTION DEBUG: Streaming update: #{message}"
    STDOUT.flush
    # Create the SSE (Server-Sent Events) format
    # Handle both string and hash data
    data = if message.is_a?(Hash)
      JSON.generate(message.merge(type: message[:type] || 'update'))
    else
      JSON.generate({ type: 'update', message: message })
    end
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
    Rails.logger.info "📝 Message length: #{response_data[:message]&.length} characters"
    Rails.logger.info "📝 Message preview: #{response_data[:message]&.first(100)}..."
    
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
      { 
        role: m.role, 
        content: m.content, 
        timestamp: m.created_at.iso8601,
        metadata: m.metadata
      }
    end
  end
  
  def save_scout_message(role, message, metadata: {})
    session_id = session[:scout_session_id]
    return unless session_id
    
    # Don't save empty messages
    return if message.blank?
    
    # Log what we're about to save
    Rails.logger.info "💾 Saving #{role} message (#{message.class}): #{message.to_s.first(200)}..."
    
    # Persist in DB (durable)
    ScoutMessage.create!(
      user_id: current_user.id,
      entity_id: current_entity&.id,
      session_id: session_id,
      role: role,
      content: message,
      metadata: metadata
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
    # Legacy method - now redirects to interactive workflow
    # The old generator canvas is deprecated in favor of interactive task workflow
    <<~HTML
      <div class="alert alert-info text-center p-4">
        <h5><i class="fas fa-info-circle me-2"></i>Landing Page Creation Updated</h5>
        <p class="mb-3">Landing page creation now uses our improved interactive workflow.</p>
        <button class="btn btn-primary" onclick="window.scoutSendMessage?.('Create a landing page')">
          <i class="fas fa-plus me-2"></i>Start Creating Landing Page
        </button>
      </div>
    HTML
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
    total_count = templates.count
    used_count = templates.joins(:campaigns).distinct.count
    
    stats = {
      total_templates: total_count,
      active_templates: used_count,
      used_templates: used_count,
      unused_templates: total_count - used_count
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

  def render_dynamic_canvas(data = {})
    render_to_string(
      partial: 'scout/canvas/dynamic_canvas',
      locals: {
        entity: current_entity,
        user: current_user,
        canvas_data: data
      }
    )
  end

  def render_interactive_wizard(data = {})
    # Convert ActionController::Parameters to hash recursively
    if data.is_a?(ActionController::Parameters)
      data = JSON.parse(data.to_json).with_indifferent_access
    end
    
    render_to_string(
      partial: 'scout/canvas/interactive_wizard',
      locals: {
        entity: current_entity,
        user: current_user,
        canvas_data: data,
        step: data[:step],
        form: data[:form],
        progress: data[:progress]
      }
    )
  end
  
  def determine_wizard_title(canvas_data)
    step = canvas_data[:step]
    progress = canvas_data[:progress]
    
    if step && step[:config] && step[:config][:title]
      step[:config][:title]
    elsif progress && progress[:workflow_type]
      case progress[:workflow_type]
      when 'landing_page_creation'
        "Landing Page Wizard"
      when 'campaign_creation'
        "Campaign Wizard"
      else
        "Interactive Wizard"
      end
    else
      "Interactive Wizard"
    end
  end
  
  def render_form_submissions_canvas(data = {})
    # Load form submissions data
    submissions_data = load_form_submissions_data(data)
    
    render_to_string(
      partial: 'scout/canvas/form_submissions',
      locals: {
        entity: current_entity,
        user: current_user,
        canvas_data: submissions_data
      }
    )
  end
  
  def load_form_submissions_data(filters = {})
    # Base query for submissions from user's landing pages
    base_query = LandingPageSubmission.joins(:landing_page)
                                      .where(landing_pages: { user: current_user, entity: current_entity })
                                      .includes(:contact, :landing_page)
    
    # Apply filters
    if filters[:landing_page_id]
      base_query = base_query.where(landing_page_id: filters[:landing_page_id])
    end
    
    if filters[:form_type].present?
      base_query = base_query.where(form_type: filters[:form_type])
    end
    
    if filters[:status].present?
      base_query = base_query.where(status: filters[:status])
    end
    
    case filters[:time_range]
    when 'today'
      base_query = base_query.today
    when 'week'
      base_query = base_query.this_week
    when 'month'
      base_query = base_query.this_month
    end
    
    # Get submissions with pagination
    submissions = base_query.recent.limit(50)
    
    # Calculate stats
    stats = calculate_submission_stats(base_query)
    
    # Format submissions for display
    formatted_submissions = submissions.map do |submission|
      {
        id: submission.id,
        form_type: submission.form_type,
        status: submission.status,
        submitted_at: submission.submitted_at.iso8601,
        processed_at: submission.processed_at&.iso8601,
        contact_info: submission.contact_info,
        utm_params: submission.utm_params,
        source_ip: submission.source_ip,
        referrer: submission.referrer,
        landing_page: {
          id: submission.landing_page.id,
          title: submission.landing_page.title,
          slug: submission.landing_page.slug
        },
        submission_data: submission.submission_data
      }
    end
    
    {
      submissions: formatted_submissions,
      stats: stats,
      landing_page: filters[:landing_page_id] ? 
        LandingPage.find_by(id: filters[:landing_page_id], user: current_user) : nil,
      pagination: {
        current_count: formatted_submissions.length,
        total_count: base_query.count,
        has_previous: false, # TODO: Implement pagination
        has_next: formatted_submissions.length >= 50
      }
    }
  end
  
  def calculate_submission_stats(base_query)
    total = base_query.count
    processed = base_query.where(status: ['processed', 'duplicate']).count
    pending = base_query.where(status: 'pending').count
    failed = base_query.where(status: 'failed').count
    spam = base_query.where(status: 'spam').count
    
    conversion_rate = total > 0 ? (processed.to_f / total * 100).round(1) : 0.0
    
    {
      total: total,
      processed: processed,
      pending: pending,
      failed: failed,
      spam: spam,
      conversion_rate: conversion_rate
    }
  end
  
  def render_workflow_analytics_canvas(data = {})
    # Load analytics data
    analytics_data = load_workflow_analytics_data(data)
    
    render_to_string(
      partial: 'scout/canvas/workflow_analytics',
      locals: {
        entity: current_entity,
        user: current_user,
        canvas_data: analytics_data
      }
    )
  end
  
  def load_workflow_analytics_data(options = {})
    period = (options[:period] || 30).to_i.days
    
    # Get analytics from ObservabilityService
    observability = ObservabilityService.instance
    
    {
      workflow_analytics: observability.workflow_analytics(period),
      tool_analytics: observability.tool_analytics(period),
      user_analytics: observability.user_analytics(period),
      ai_metrics: observability.ai_metrics(period),
      performance_metrics: observability.performance_metrics(period),
      period_days: period.to_i / 1.day,
      generated_at: Time.current
    }
  end

  def render_task_progress(data = {})
    # Handle both symbol and string keys
    data = data.with_indifferent_access if data.is_a?(Hash)
    
    # If no data provided, try to load from TaskSession
    if data.empty? || data.nil? || data[:tasks].nil?
      session_id = session[:scout_session_id]
      
      # Try to find active task session
      task_session = TaskSession.active
                               .where(user: current_user)
                               .where("metadata->>'session_id' = ?", session_id)
                               .first
      
      if task_session
        # Check if we have a task list in state
        if task_session.state&.dig('task_list')
          data = task_session.state['task_list']
          Rails.logger.info "📋 Loaded task list from TaskSession state: #{data[:tasks]&.size} tasks"
        elsif task_session.workflow_spec
          # Convert workflow to task list format for display with proper state restoration
          workflow_engine = WorkflowEngine.new(task_session)
          workflow_progress = workflow_engine.progress
          
          # Get workflow instance to access steps
          workflow = workflow_engine.instance_variable_get(:@workflow)
          
          data = {
            tasks: workflow.steps.map do |step|
              {
                id: step.id,
                description: step.description,
                status: step.status
              }
            end,
            workflow_status: workflow_progress[:status],
            progress: workflow_progress
          }
          Rails.logger.info "📋 Loaded task list from TaskSession workflow: #{data[:tasks]&.size} tasks"
        else
          Rails.logger.info "📋 TaskSession found but no task list or workflow"
          data = { tasks: [] }
        end
      else
        Rails.logger.info "📋 No active task session found for session: #{session_id}"
        data = { tasks: [] }
      end
    else
      Rails.logger.info "📋 Using provided task data: #{data[:tasks]&.size} tasks"
    end
    
    render_to_string(
      partial: 'scout/canvas/task_progress',
      locals: {
        entity: current_entity,
        user: current_user,
        task_list: data
      }
    )
  end

  def render_integrations_manager(data = {})
    render partial: 'scout/canvas/integrations_manager', locals: { canvas_data: data }
  end

  def render_campaign_editor(data = {})
    # Load campaign if ID provided
    campaign = if data[:campaign_id]
      current_entity.campaigns.find_by(id: data[:campaign_id])
    else
      current_entity.campaigns.build
    end
    
    # Load contact groups and email templates
    contact_groups = current_entity.contact_groups.active
    email_templates = current_entity.email_templates
    
    render_to_string(
      partial: 'scout/canvas/campaign_editor',
      locals: {
        campaign: campaign,
        contact_groups: contact_groups,
        email_templates: email_templates,
        entity: current_entity,
        user: current_user,
        data: data
      }
    )
  end
end 