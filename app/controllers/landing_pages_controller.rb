class LandingPagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_landing_page, only: [:show, :edit, :update, :destroy, :publish, :unpublish, :preview, :generate_image, :generate_content, :chat_preview, :apply_change, :no_header_preview, :get_chat_messages]
  
  def index
    @landing_pages = current_user.landing_pages.where(entity_id: current_entity.id).order(created_at: :desc)
  end

  def show
  end

  def new
    @landing_page = current_user.landing_pages.new(entity_id: current_entity.id)
    
    # Get business profile for context in the wizard
    @business_profile = current_entity.business_profiles.first || current_user.business_profile
    
    # Pre-populate campaign info if provided
    if params[:campaign_id].present?
      @campaign = current_user.campaigns.where(entity_id: current_entity.id).find_by(id: params[:campaign_id])
      if @campaign
        @landing_page.campaign_id = @campaign.id
        @landing_page.title = "Landing page for #{@campaign.name}"
      end
    end
  end

  def create
    @landing_page = current_user.landing_pages.new(landing_page_params)
    @landing_page.entity_id = current_entity.id
    
    # Get business profile for context
    @business_profile = current_entity.business_profiles.first || current_user.business_profile
    
    if @landing_page.save
      case params[:action]
      when 'save_draft'
        # Just save as draft and redirect to edit
        redirect_to edit_landing_page_path(@landing_page), notice: 'Landing page draft was successfully created.'
      when 'generate_and_preview'
        # Generate content with AI and redirect to chat preview
        generate_initial_content
        redirect_to chat_preview_landing_page_path(@landing_page), notice: 'Landing page is being generated with AI. You can make further adjustments using the chat interface.'
      else
        # Default behavior
        redirect_to edit_landing_page_path(@landing_page), notice: 'Landing page was successfully created.'
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    # Get business profile for context in AI generation
    @business_profile = current_entity.business_profiles.first || current_user.business_profile
  end

  def update
    if @landing_page.update(landing_page_params)
      redirect_to landing_pages_path, notice: 'Landing page was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @landing_page.destroy
    redirect_to landing_pages_path, notice: 'Landing page was successfully deleted.'
  end
  
  def publish
    if @landing_page.update(published: true, status: 'published')
      redirect_to landing_pages_path, notice: 'Landing page has been published.'
    else
      redirect_to edit_landing_page_path(@landing_page), alert: 'Unable to publish landing page.'
    end
  end
  
  def unpublish
    if @landing_page.update(published: false, status: 'draft')
      redirect_to landing_pages_path, notice: 'Landing page has been unpublished.'
    else
      redirect_to edit_landing_page_path(@landing_page), alert: 'Unable to unpublish landing page.'
    end
  end
  
  def preview
    respond_to do |format|
      format.html { render layout: 'landing_page_preview', inline: "" }
      format.json { render json: @landing_page.preview_data }
    end
  end
  
  def no_header_preview
    respond_to do |format|
      format.html { render layout: 'landing_page_content_only', inline: "" }
    end
  end
  
  def generate_content
    # Prepare context for AI generation
    business_profile = current_entity.business_profiles.first || current_user.business_profile
    
    topic = params[:description]
    page_type = params[:page_type] || 'lead_generation'
    
    # Use the new multi-agent system for content generation
    AgentGenerateLandingPageJob.perform_later(
      @landing_page.id,
      topic,
      current_entity.id,
      business_profile&.id,
      page_type
    )
    
    redirect_to edit_landing_page_path(@landing_page), notice: 'Content generation has been started using our advanced AI agent system. This process may take a bit longer but will produce higher quality results.'
  end
  
  def generate_image
    description = params[:image_description]
    section = params[:section] || 'hero'
    
    # Create the AI image generation job
    GenerateLandingPageImageJob.perform_later(
      @landing_page.id, 
      description, 
      section
    )
    
    redirect_to edit_landing_page_path(@landing_page), notice: 'Image generation has been started. This may take a few moments.'
  end
  
  def chat_preview
    # Get business profile for context in AI generation
    @business_profile = current_entity.business_profiles.first || current_user.business_profile
    
    respond_to do |format|
      format.html { render layout: 'landing_page_chat' }
    end
  end
  
  def apply_change
    # Handle AI-requested changes via chat interface
    instruction = params[:instruction]
    section_index = params[:section_index]
    
    # Attempt to automatically detect which section to edit if not specified
    if section_index.nil? && instruction.present?
      # Look for numeric patterns like "section 2" or "section #3"
      section_match = instruction.match(/section\s+[#]?(\d+)/i)
      if section_match
        # Convert to 0-indexed
        section_index = section_match[1].to_i - 1
        section_index = nil if section_index < 0
      end
    end
    
    # Store user's message
    user_message = @landing_page.landing_page_chat_messages.create!(
      content: instruction,
      role: 'user',
      user: current_user
    )
    
    # Get conversation history
    conversation_history = @landing_page.landing_page_chat_messages.conversation_history(@landing_page.id)
    
    # Log the request
    Rails.logger.info("Chat request from user #{current_user.id} for landing page #{@landing_page.id}: #{instruction}")
    Rails.logger.info("Targeting section index: #{section_index || 'general edit'}")
    Rails.logger.info("Conversation history: #{conversation_history.to_json}")
    
    # Create a job to apply the change
    ApplyLandingPageChangeJob.perform_later(
      @landing_page.id,
      instruction,
      current_entity.id,
      current_user.id,
      conversation_history: conversation_history,
      message_id: user_message.id,
      section_index: section_index,
      correlation_id: SecureRandom.uuid
    )
    
    render json: { 
      status: 'processing',
      message: 'Your request is being processed. The page will update shortly.',
      message_id: user_message.id
    }
  end
  
  def get_chat_messages
    @landing_page = current_user.landing_pages.where(entity_id: current_entity.id).find(params[:id])
    messages = @landing_page.landing_page_chat_messages.order(created_at: :asc)
    
    render json: { 
      messages: messages.map do |msg|
        {
          id: msg.id,
          content: msg.content,
          role: msg.role,
          timestamp: msg.created_at.iso8601
        }
      end
    }
  end
  
  # Public-facing landing page view (no auth required)
  def public_view
    @landing_page = LandingPage.published.find_by!(slug: params[:slug])
    
    # Track the view
    track_landing_page_view
    
    render layout: 'landing_page', inline: ""
  rescue ActiveRecord::RecordNotFound
    render file: "#{Rails.root}/public/404.html", layout: false, status: :not_found
  end
  
  # Show version history
  def versions
    @versions = @landing_page.landing_page_versions.order(created_at: :desc)
    
    respond_to do |format|
      format.html
      format.json { render json: @versions }
    end
  end
  
  # Rollback to a specific version
  def rollback
    @version = @landing_page.landing_page_versions.find(params[:version_id])
    
    if @version.restore
      respond_to do |format|
        format.html { redirect_to edit_landing_page_path(@landing_page), notice: "Successfully rolled back to previous version." }
        format.json { render json: { status: "success", message: "Successfully rolled back to previous version." } }
      end
    else
      respond_to do |format|
        format.html { redirect_to edit_landing_page_path(@landing_page), alert: "Failed to rollback to previous version." }
        format.json { render json: { status: "error", message: "Failed to rollback to previous version." }, status: :unprocessable_entity }
      end
    end
  end
  
  private
  
  def set_landing_page
    @landing_page = current_user.landing_pages.where(entity_id: current_entity.id).find(params[:id])
  end
  
  def landing_page_params
    params.require(:landing_page).permit(
      :title, 
      :slug, 
      :description,
      :headline,
      :subheadline,
      :cta_text,
      :cta_url,
      :status,
      :page_type,
      :campaign_id,
      :custom_domain,
      :published,
      :primary_color,
      :secondary_color,
      :font_family,
      :image_url,
      :meta_description,
      :meta_keywords,
      :tone_preference,
      :content_length,
      :include_testimonials,
      :include_features,
      :include_faq,
      :include_pricing,
      :include_about,
      :include_contact,
      content: [
        :title,
        :content,
        :type,
        :section_index,
        :image_url
      ]
    )
  end
  
  def track_landing_page_view
    # Implement view tracking logic here
    # Could record visitor info, referrer, etc.
  end
  
  def generate_initial_content
    # Build comprehensive context for AI generation
    context = {
      business_profile: @business_profile,
      design_preferences: {
        page_type: @landing_page.page_type,
        tone_preference: @landing_page.tone_preference,
        content_length: @landing_page.content_length,
        primary_color: @landing_page.primary_color,
        secondary_color: @landing_page.secondary_color,
        font_family: @landing_page.font_family
      },
      features: {
        include_testimonials: @landing_page.include_testimonials,
        include_features: @landing_page.include_features,
        include_faq: @landing_page.include_faq,
        include_pricing: @landing_page.include_pricing,
        include_about: @landing_page.include_about,
        include_contact: @landing_page.include_contact
      }
    }
    
    # Use the enhanced AI generation job with all context
    AgentGenerateLandingPageJob.perform_later(
      @landing_page.id,
      @landing_page.description,
      current_entity.id,
      @business_profile&.id,
      @landing_page.page_type,
      context
    )
  end
end 