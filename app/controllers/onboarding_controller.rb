class OnboardingController < ApplicationController
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
    
    if user_message.blank?
      render json: { error: 'Message cannot be empty' }, status: 400
      return
    end
    
    begin
      # Save user message
      save_onboarding_message('user', user_message)
      
      # Get Scout's response
      response = OnboardingScoutService.new(current_user, @session_id).process_message(user_message)
      
      # Save Scout's response
      save_onboarding_message('assistant', response[:message])
      
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
    session.delete(:onboarding_session_id)
    
    redirect_to root_path, notice: "Welcome to Crux Marketing! Scout is ready to help you grow your business."
  end
  
  private
  
  def check_if_already_onboarded
    if current_user.onboarded?
      redirect_to root_path, notice: "You've already completed onboarding!"
    end
  end
  
  def create_welcome_message
    welcome_message = "👋 Hi #{current_user.first_name}! I'm Scout, your AI marketing agent. 

I'm here to learn about your business so I can help you create amazing campaigns. This will only take a few minutes, and I promise to make it conversational - no boring forms!

Let's start simple: What's the name of your business?"

    save_onboarding_message('assistant', welcome_message)
  end
  
  def save_onboarding_message(role, content)
    # We'll store onboarding conversations separately from regular scout conversations
    session[:onboarding_messages] ||= []
    session[:onboarding_messages] << {
      role: role,
      content: content,
      timestamp: Time.current.iso8601
    }
  end
  
  def onboarding_conversation_history
    session[:onboarding_messages] || []
  end
end 