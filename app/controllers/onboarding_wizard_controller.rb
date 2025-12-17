class OnboardingWizardController < ApplicationController
  before_action :authenticate_user!
  before_action :set_step
  before_action :set_step_info
  
  layout "onboarding"

  # Step definitions - usage_type determines if we show business steps
  STEPS = %w[welcome about_you usage_type website your_business use_cases features complete].freeze

  def show

    case @step
    when 'welcome'
      # No data needed
    when 'about_you'
      @user = current_user
    when 'usage_type'
      @usage_type = session[:onboarding_usage_type] || 'work'
    when 'website'
      @website_url = session[:onboarding_website_url]
      @website_analyzed = session[:onboarding_website_data].present?
    when 'your_business'
      @business_profile = current_entity.business_profiles.first_or_initialize
      # Pre-populate from website analysis if available
      prefill_business_from_website_data
    when 'use_cases'
      @selected_use_cases = session[:onboarding_use_cases] || []
      @usage_type = session[:onboarding_usage_type] || 'work'
    when 'features'
      @feature_categories = available_feature_categories
      @selected_features = session[:onboarding_features] || default_features
    when 'complete'
      finalize_onboarding if request.get?
    end

    render @step
  end

  def update
    case @step
    when 'welcome'
      redirect_to onboarding_path(step: 'about_you')

    when 'about_you'
      if current_user.update(user_params)
        redirect_to onboarding_path(step: 'usage_type')
      else
        @user = current_user
        render :about_you
      end

    when 'usage_type'
      usage_type = params[:usage_type] || 'work'
      session[:onboarding_usage_type] = usage_type
      
      # Skip website and business if personal use
      if usage_type == 'personal'
        redirect_to onboarding_path(step: 'use_cases')
      else
        redirect_to onboarding_path(step: 'website')
      end

    when 'website'
      website_url = params[:website_url]&.strip
      
      if website_url.present?
        # Store the URL and analyze the website
        session[:onboarding_website_url] = website_url
        analyze_website(website_url)
      else
        # No website provided, clear any previous data
        session.delete(:onboarding_website_url)
        session.delete(:onboarding_website_data)
      end
      
      redirect_to onboarding_path(step: 'your_business')

    when 'your_business'
      @business_profile = current_entity.business_profiles.first_or_initialize
      @business_profile.assign_attributes(business_profile_params)
      @business_profile.user ||= current_user
      if @business_profile.save
        redirect_to onboarding_path(step: 'use_cases')
      else
        Rails.logger.error "[Onboarding] BusinessProfile save failed: #{@business_profile.errors.full_messages.join(', ')}"
        flash.now[:alert] = @business_profile.errors.full_messages.join(', ')
        render :your_business
      end

    when 'use_cases'
      session[:onboarding_use_cases] = params[:use_cases] || []
      redirect_to onboarding_path(step: 'features')

    when 'features'
      session[:onboarding_features] = params[:features] || []
      redirect_to onboarding_path(step: 'complete')

    when 'complete'
      finalize_onboarding
      redirect_to chat_mode_path, notice: "Welcome to Amos! Your workspace is ready."
    end
  end

  def skip
    # Mark onboarding as skipped but complete with default settings
    space_pref = current_user.space_preference || current_user.build_space_preference
    space_pref.enabled_spaces = ['team', 'work'] # Default to team + work
    space_pref.active_space = 'work'
    space_pref.onboarding_completed = true
    space_pref.save!
    
    # Also mark user as onboarded
    current_user.update!(onboarded: true) unless current_user.onboarded?
    
    redirect_to chat_mode_path, notice: "Onboarding skipped. You can configure your workspace anytime in Settings."
  end

  private

  def set_step
    @step = params[:step] || 'welcome'
    unless STEPS.include?(@step)
      redirect_to onboarding_path(step: 'welcome')
    end
  end

  def user_params
    params.require(:user).permit(:first_name, :last_name, :job_title)
  end

  def business_profile_params
    params.require(:business_profile).permit(:name, :industry, :company_size, :website, :description, :target_audience, :tone_of_voice, :values)
  end

  def set_step_info
    @total_steps = STEPS.length
    @current_step_index = STEPS.index(@step) + 1
  end

  def available_feature_categories
    [
      {
        slug: 'marketing',
        name: 'Marketing & Campaigns',
        description: 'Landing pages, email campaigns, contact management',
        icon: 'megaphone',
        features: %w[landing_pages campaigns email_templates contacts]
      },
      {
        slug: 'automation',
        name: 'Automation & Integrations',
        description: 'Connect apps, automate workflows, scheduled tasks',
        icon: 'zap',
        features: %w[integrations scheduled_tasks workflows]
      },
      {
        slug: 'analytics',
        name: 'Analytics & Insights',
        description: 'Performance tracking, reports, data visualization',
        icon: 'bar-chart-2',
        features: %w[analytics dashboards reports]
      },
      {
        slug: 'content',
        name: 'Content & Documents',
        description: 'Document storage, AI content generation',
        icon: 'file-text',
        features: %w[documents knowledge_base content_generation]
      },
      {
        slug: 'collaboration',
        name: 'Team Collaboration',
        description: 'Team channels, shared tasks, agent coordination',
        icon: 'users',
        features: %w[team_channels shared_tasks agents]
      }
    ]
  end

  def default_features
    %w[landing_pages campaigns contacts analytics integrations documents]
  end

  def finalize_onboarding
    # Mark user as onboarded
    current_user.update!(onboarded: true) unless current_user.onboarded?
    
    # Determine spaces based on usage type
    usage_type = session[:onboarding_usage_type] || 'work'
    
    # Team space is always enabled (agent interaction hub)
    # Add the usage type space (personal or work)
    enabled_spaces = ['team', usage_type].uniq
    starting_space = usage_type # Start in their chosen context
    
    # Create/update user space preferences
    space_pref = current_user.space_preference || current_user.build_space_preference
    space_pref.enabled_spaces = enabled_spaces
    space_pref.active_space = starting_space
    space_pref.onboarding_completed = true
    space_pref.save!

    # Create menu configurations based on selected features
    selected_features = session[:onboarding_features] || default_features
    
    SpaceDefinition::ALL_SPACES.each do |space_slug|
      config = current_user.menu_config_for_space(space_slug)
      space_def = SpaceDefinition.find_by(slug: space_slug)
      
      # Use intersection of selected features and space defaults
      visible = space_def&.default_menu_items&.select { |item| selected_features.include?(item) } || []
      config.update!(visible_items: visible)
    end

    # Clear session data
    session.delete(:onboarding_website_url)
    session.delete(:onboarding_website_data)
    session.delete(:onboarding_use_cases)
    session.delete(:onboarding_features)
    session.delete(:onboarding_usage_type)
  end

  def analyze_website(url)
    Rails.logger.info "[Onboarding] Analyzing website: #{url}"
    
    begin
      analyzer = OnboardingWebsiteAnalyzerService.new(url: url)
      result = analyzer.analyze
      
      if result[:success]
        # Store the extracted data in session
        session[:onboarding_website_data] = {
          'business_name' => result[:business_name],
          'industry' => result[:industry],
          'description' => result[:description],
          'tagline' => result[:tagline],
          'products_services' => result[:products_services],
          'target_audience' => result[:target_audience],
          'company_size_hint' => result[:company_size_hint],
          'tone_of_voice' => result[:tone_of_voice],
          'values' => result[:values],
          'website' => url
        }
        Rails.logger.info "[Onboarding] Website analysis successful: #{result[:business_name]}"
      else
        Rails.logger.warn "[Onboarding] Website analysis failed: #{result[:error]}"
        session[:onboarding_website_data] = { 'website' => url }
      end
    rescue => e
      Rails.logger.error "[Onboarding] Website analysis error: #{e.message}"
      session[:onboarding_website_data] = { 'website' => url }
    end
  end

  def prefill_business_from_website_data
    data = session[:onboarding_website_data]
    return unless data.present?

    # Pre-fill fields that haven't been set yet
    if @business_profile.name.blank? && data['business_name'].present?
      @business_profile.name = data['business_name']
    end
    
    if @business_profile.industry.blank? && data['industry'].present?
      @business_profile.industry = data['industry']
    end
    
    if @business_profile.website.blank? && data['website'].present?
      @business_profile.website = data['website']
    end
    
    if @business_profile.description.blank? && data['description'].present?
      @business_profile.description = data['description']
    end
    
    if @business_profile.company_size.blank? && data['company_size_hint'].present?
      @business_profile.company_size = data['company_size_hint']
    end
    
    if @business_profile.target_audience.blank? && data['target_audience'].present?
      @business_profile.target_audience = data['target_audience']
    end
    
    if @business_profile.tone_of_voice.blank? && data['tone_of_voice'].present?
      @business_profile.tone_of_voice = data['tone_of_voice']
    end
    
    if @business_profile.values.blank? && data['values'].present?
      @business_profile.values = data['values']
    end
    
    # Store additional context for display
    @website_insights = {
      tagline: data['tagline'],
      products_services: data['products_services']
    }
  end
end
