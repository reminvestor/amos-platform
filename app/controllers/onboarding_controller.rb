class OnboardingController < ApplicationController
  layout 'devise'
  
  before_action :authenticate_user!
  before_action :check_if_already_onboarded, except: [:complete]
  
  def index
    # Get or create the user's first onboarding conversation
    @session_id = session[:onboarding_session_id] ||= SecureRandom.uuid
    @conversation_history = onboarding_conversation_history
    
    # If this is a fresh start, add Scout's welcome message
    if @conversation_history.empty?
      create_welcome_message
      @conversation_history = onboarding_conversation_history
    end
  end
  
  def chat
    @session_id = session[:onboarding_session_id] ||= SecureRandom.uuid
    user_message = params[:message]&.strip
    
    Rails.logger.info "Onboarding chat - Session: #{@session_id}, User: #{current_user.id}, Message: #{user_message}"
    
    if user_message.blank?
      render json: { error: 'Message cannot be empty' }, status: 400
      return
    end
    
    begin
      # Save user message
      save_onboarding_message('user', user_message)
      Rails.logger.info "Onboarding: Saved user message"
      
      # Get Scout's response with conversation history
      conversation_history = onboarding_conversation_history
      Rails.logger.info "Onboarding: Retrieved conversation history (#{conversation_history.length} messages)"
      
      response = OnboardingScoutService.new(current_user, @session_id, conversation_history).process_message(user_message)
      Rails.logger.info "Onboarding: Got Scout response - completed: #{response[:completed]}"
      
      # Save Scout's response
      save_onboarding_message('assistant', response[:message])
      Rails.logger.info "Onboarding: Saved Scout response"
      
      render json: {
        message: response[:message],
        completed: response[:completed],
        business_profile_completed: response[:business_profile_completed]
      }
    rescue => e
      Rails.logger.error "Onboarding chat error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      fallback_message = "I'm having a moment! Let me try that again. What can you tell me about your business?"
      save_onboarding_message('assistant', fallback_message)
      
      render json: { message: fallback_message }
    end
  end
  
  def complete
    # Mark user as onboarded and redirect to main app
    current_user.update(onboarded: true)
    
    # Clear conversation cache
    if session[:onboarding_session_id].present?
      Rails.cache.delete("onboarding_#{session[:onboarding_session_id]}")
    end
    session.delete(:onboarding_session_id)
    
    # Redirect to app subdomain for main application
    app_url = root_url(subdomain: 'app')
    redirect_to app_url, notice: "Welcome to Crux Marketing! Scout is ready to help you grow your business."
  end
  
  def reset
    # Clear conversation history and start fresh
    if session[:onboarding_session_id].present?
      Rails.cache.delete("onboarding_#{session[:onboarding_session_id]}")
    end
    session.delete(:onboarding_session_id)
    
    redirect_to onboarding_path, notice: "Conversation reset. Starting fresh with Scout!"
  end
  
  private
  
  def check_if_already_onboarded
    if current_user.onboarded?
      redirect_to root_path, notice: "You've already completed onboarding!"
    end
  end
  
  def create_welcome_message
    entity = current_user.entities.first
    business_name = entity&.name || "your business"
    
    welcome_message = "👋 Hi #{current_user.first_name}! I'm Scout, your AI marketing agent. 

I see you're working with #{business_name} - that's exciting! I'm here to learn more about your business so I can help you create amazing campaigns. This will only take a few minutes, and I promise to make it conversational - no boring forms!

Since I already know your business name, let's dive deeper: What industry is #{business_name} in? Are you in tech, retail, healthcare, consulting, or something else?"

    save_onboarding_message('assistant', welcome_message)
  end
  
  def save_onboarding_message(role, content)
    # Store onboarding conversations only in Rails cache to avoid cookie overflow
    cache_key = "onboarding_#{session[:onboarding_session_id]}"
    messages = Rails.cache.read(cache_key) || []
    messages << {
      role: role,
      content: content,
      timestamp: Time.current.iso8601
    }
    
    # Store in cache with 2 hour expiration
    Rails.cache.write(cache_key, messages, expires_in: 2.hours)
  end
  
  def onboarding_conversation_history
    # Read from cache only to avoid cookie overflow
    cache_key = "onboarding_#{session[:onboarding_session_id]}"
    messages = Rails.cache.read(cache_key) || []
    
    # Ensure we return properly formatted messages
    messages.map do |msg|
      {
        role: msg[:role] || msg['role'],
        content: msg[:content] || msg['content'],
        timestamp: msg[:timestamp] || msg['timestamp'] || Time.current.iso8601
      }
    end
  end
end 