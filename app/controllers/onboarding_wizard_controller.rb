class OnboardingWizardController < ApplicationController
  before_action :authenticate_user!
  before_action :set_step
  
  layout "onboarding"

  # Step definitions
  STEPS = %w[welcome about_you your_business use_cases features spaces complete].freeze

  def show
    @total_steps = STEPS.length
    @current_step_index = STEPS.index(@step) + 1

    case @step
    when 'welcome'
      # No data needed
    when 'about_you'
      @user = current_user
    when 'your_business'
      @business_profile = current_entity.business_profiles.first_or_initialize
    when 'use_cases'
      @selected_use_cases = session[:onboarding_use_cases] || []
    when 'features'
      @feature_categories = available_feature_categories
      @selected_features = session[:onboarding_features] || default_features
    when 'spaces'
      @spaces = SpaceDefinition.enabled.ordered
      @enabled_spaces = session[:onboarding_spaces] || SpaceDefinition::ALL_SPACES
      @starting_space = session[:onboarding_starting_space] || 'work'
    when 'complete'
      finalize_onboarding if request.get?
    end

    render @step
  end

  def update
    case @step
    when 'welcome'
      redirect_to onboarding_wizard_path(step: 'about_you')

    when 'about_you'
      if current_user.update(user_params)
        redirect_to onboarding_wizard_path(step: 'your_business')
      else
        @user = current_user
        render :about_you
      end

    when 'your_business'
      @business_profile = current_entity.business_profiles.first_or_initialize
      @business_profile.assign_attributes(business_profile_params)
      if @business_profile.save
        redirect_to onboarding_wizard_path(step: 'use_cases')
      else
        render :your_business
      end

    when 'use_cases'
      session[:onboarding_use_cases] = params[:use_cases] || []
      redirect_to onboarding_wizard_path(step: 'features')

    when 'features'
      session[:onboarding_features] = params[:features] || []
      redirect_to onboarding_wizard_path(step: 'spaces')

    when 'spaces'
      session[:onboarding_spaces] = params[:enabled_spaces] || SpaceDefinition::ALL_SPACES
      session[:onboarding_starting_space] = params[:starting_space] || 'work'
      redirect_to onboarding_wizard_path(step: 'complete')

    when 'complete'
      finalize_onboarding
      redirect_to chat_mode_path, notice: "Welcome to Amos! Your workspace is ready."
    end
  end

  def skip
    # Mark onboarding as skipped but complete
    space_pref = current_user.space_preference || current_user.build_space_preference
    space_pref.update!(onboarding_completed: true)
    
    redirect_to chat_mode_path, notice: "Onboarding skipped. You can configure your workspace anytime in Settings."
  end

  private

  def set_step
    @step = params[:step] || 'welcome'
    unless STEPS.include?(@step)
      redirect_to onboarding_wizard_path(step: 'welcome')
    end
  end

  def user_params
    params.require(:user).permit(:first_name, :last_name, :job_title)
  end

  def business_profile_params
    params.require(:business_profile).permit(:name, :industry, :company_size, :website, :description)
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
    # Create/update user space preferences
    space_pref = current_user.space_preference || current_user.build_space_preference
    space_pref.enabled_spaces = session[:onboarding_spaces] || SpaceDefinition::ALL_SPACES
    space_pref.active_space = session[:onboarding_starting_space] || 'work'
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
    session.delete(:onboarding_use_cases)
    session.delete(:onboarding_features)
    session.delete(:onboarding_spaces)
    session.delete(:onboarding_starting_space)
  end
end
