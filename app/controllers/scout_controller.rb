class ScoutController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_entity_exists
  before_action :ensure_onboarded
  
  layout 'workspace'
  
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
        error_count: response[:error_count]
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

    response.headers['Content-Type'] = 'text/plain'
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['Connection'] = 'keep-alive'
    
    begin
      # Save user message
      save_scout_message('user', user_message)
      stream_update("💬 Message received")
      
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
    response.stream.write("data: #{JSON.generate({ type: 'update', message: message })}\n\n")
  end

  def stream_final_response(response_data)
    response.stream.write("data: #{JSON.generate({ type: 'response', data: response_data })}\n\n")
  end
  
  def current_entity
    @current_entity ||= current_user.entity_users.first&.entity
  end
  
  def ensure_entity_exists
    unless current_entity
      redirect_to root_path, alert: "You need to set up your business profile first."
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
end 