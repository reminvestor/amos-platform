class OnboardingController < ApplicationController
  layout "onboarding"

  before_action :authenticate_user!
  before_action :check_if_already_onboarded, except: [ :complete ]

  def index
    Rails.logger.info "🔍 Onboarding#index - User: #{current_user.id}, Onboarded: #{current_user.onboarded?}, Path: #{request.path}"
    Rails.logger.info "🔍 Session flags - show_subscription_confirmation: #{session[:show_subscription_confirmation]}, subscription_confirmed: #{session[:subscription_confirmed]}"
    
    # Get or create the user's first onboarding conversation
    @session_id = session[:onboarding_session_id] ||= SecureRandom.uuid
    @conversation_history = onboarding_conversation_history

    # If user just subscribed and was previously onboarded, reset their onboarded status
    if session[:show_subscription_confirmation] && current_user.onboarded?
      Rails.logger.info "🔄 Resetting onboarded status for user #{current_user.id} after subscription"
      current_user.update!(onboarded: false)
    end

    # If this is a fresh start, add Scout's welcome message
    if @conversation_history.empty?
      # Check if user just subscribed (coming from Stripe checkout)
      entity = current_user.entity
      if entity&.subscription_status == 'trialing' && entity.trial_ends_at
        # User just subscribed, add subscription confirmation in welcome message
      end
      create_welcome_message
      @conversation_history = onboarding_conversation_history
    elsif session[:show_subscription_confirmation] && !session[:subscription_confirmed]
      # User returned from Stripe, prepend confirmation to existing conversation
      prepend_subscription_confirmation_message
      session[:subscription_confirmed] = true
      session.delete(:show_subscription_confirmation)
      @conversation_history = onboarding_conversation_history
    end
  end

  def chat
    @session_id = session[:onboarding_session_id] ||= SecureRandom.uuid
    user_message = params[:message]&.strip

    Rails.logger.info "Onboarding chat - Session: #{@session_id}, User: #{current_user.id}, Message: #{user_message}"

    if user_message.blank?
      render json: { error: "Message cannot be empty" }, status: 400
      return
    end

    begin
      # Save user message
      save_onboarding_message("user", user_message)
      Rails.logger.info "Onboarding: Saved user message"

      # Get Scout's response with conversation history
      conversation_history = onboarding_conversation_history
      Rails.logger.info "Onboarding: Retrieved conversation history (#{conversation_history.length} messages)"

      # Regular onboarding conversation (V3 handles tools automatically)
      response = OnboardingScoutService.new(current_user, @session_id, conversation_history).process_message(user_message)

      Rails.logger.info "Onboarding: Got Scout response - completed: #{response[:completed]}, tools_used: #{response[:tools_used]}"

      # Save Scout's response
      save_onboarding_message("assistant", response[:message])
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
      save_onboarding_message("assistant", fallback_message)

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

    # Redirect to Scout (main app)
    redirect_to scout_path, notice: "Welcome to Amos! Your AI business automation assistant is ready to help you succeed."
  end

  def reset
    # Clear conversation history and start fresh
    if session[:onboarding_session_id].present?
      Rails.cache.delete("onboarding_#{session[:onboarding_session_id]}")
    end
    session.delete(:onboarding_session_id)

    redirect_to onboarding_path, notice: "Conversation reset. Starting fresh with Amos!"
  end

  # Debug action to check user status without redirects
  def debug_status
    render json: {
      user_id: current_user.id,
      onboarded: current_user.onboarded?,
      entities_count: current_user.entity ? 1 : 0,
      domain: request.domain,
      subdomain: request.subdomain,
      path: request.path,
      has_business_profile: current_user.business_profile.present?,
      session_show_subscription_confirmation: session[:show_subscription_confirmation],
      session_subscription_confirmed: session[:subscription_confirmed],
      entity_subscription_status: current_user.entity&.subscription_status,
      entity_trial_ends_at: current_user.entity&.trial_ends_at,
      entity_name: current_user.entity&.name
    }
  end

  private

  def needs_tool_enabled_response?(message)
    # Detect if user is asking questions that would benefit from real data access
    data_keywords = [
      /campaign/i, /email.*performance/i, /marketing.*data/i, /analytics/i,
      /open.*rate/i, /click.*rate/i, /subscriber/i, /contact/i,
      /landing.*page/i, /conversion/i, /engagement/i, /metrics/i,
      /how.*\w+.*performing/i, /show.*\w+.*stats/i, /analyze/i
    ]

    data_keywords.any? { |pattern| message.match?(pattern) }
  end

  def check_if_already_onboarded
    # Debug logging for production troubleshooting
    Rails.logger.info "🔍 Onboarding controller check - User: #{current_user.id}, Onboarded: #{current_user.onboarded?}, Path: #{request.path}, Domain: #{request.domain}"
    Rails.logger.info "🔍 Session flags - show_subscription_confirmation: #{session[:show_subscription_confirmation]}, subscription_confirmed: #{session[:subscription_confirmed]}"

    # TEMPORARY FIX: Always allow onboarding for users with active subscription who haven't completed onboarding
    entity = current_user.entity
    if entity && ['active', 'trialing'].include?(entity.subscription_status) && !current_user.onboarded?
      Rails.logger.info "🔄 User has active subscription but not onboarded, allowing onboarding - User: #{current_user.id}"
      return # Allow onboarding to proceed
    end

    # Allow users to continue onboarding if they just subscribed (coming from Stripe)
    if current_user.onboarded? && !session[:show_subscription_confirmation]
      Rails.logger.info "🔄 User already onboarded, redirecting to scout - User: #{current_user.id}"
      # Redirect to scout (main app) instead of root to avoid redirect loop
      redirect_to scout_path, notice: "You've already completed onboarding!"
    end
  end

  def create_welcome_message
    # User has 1:1 relationship with entity
    entity = current_user.entity
    business_name = entity&.name || "your business"

    # Check if user just subscribed (has trial status and recent subscription)
    subscription_info = if entity&.subscription_status == 'trialing' && entity.trial_ends_at
      plan_name = entity.plan_tier&.titleize || 'Starter'
      trial_end = entity.trial_ends_at.strftime('%B %d, %Y')
      "\n🎉 Great news! Your #{plan_name} plan 7-day trial has started successfully. You won't be charged until #{trial_end}.\n\n"
    else
      ""
    end

    welcome_message = "Hi #{current_user.first_name}! I'm Amos, your AI business automation assistant.#{subscription_info}
I see you're working with #{business_name} - that's exciting! I'm here to learn more about your business so I can help you automate workflows, manage integrations, analyze data, run marketing campaigns, and much more. This will only take a few minutes, and I promise to make it conversational - no boring forms!

Since I already know your business name, let's dive deeper: What industry is #{business_name} in? Are you in tech, retail, healthcare, consulting, or something else?"

    save_onboarding_message("assistant", welcome_message)
  end

  def add_subscription_confirmation_message
    entity = current_user.entity
    plan_name = entity.plan_tier&.titleize || 'Starter'
    trial_end = entity.trial_ends_at.strftime('%B %d, %Y')

    confirmation = "🎉 **Subscription Confirmed!**\n\nYour #{plan_name} plan 7-day trial has started successfully. You won't be charged until #{trial_end}.\n\nNow let's get your business set up!"

    save_onboarding_message('assistant', confirmation)
  end

  def prepend_subscription_confirmation_message
    entity = current_user.entity
    plan_name = entity.plan_tier&.titleize || 'Starter'
    trial_end = entity.trial_ends_at.strftime('%B %d, %Y')

    confirmation = "🎉 **Welcome back!** Your #{plan_name} plan 7-day trial has started successfully. You won't be charged until #{trial_end}.\n\nLet's continue setting up your business!"

    save_onboarding_message('assistant', confirmation)
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
        role: msg[:role] || msg["role"],
        content: msg[:content] || msg["content"],
        timestamp: msg[:timestamp] || msg["timestamp"] || Time.current.iso8601
      }
    end
  end
end
