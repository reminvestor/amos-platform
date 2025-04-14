class LandingPagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_landing_page, only: [:show, :edit, :update, :destroy, :publish, :unpublish, :preview, :generate_image, :generate_content]
  
  def index
    @landing_pages = current_user.landing_pages.where(entity_id: current_entity.id).order(created_at: :desc)
  end

  def show
  end

  def new
    @landing_page = current_user.landing_pages.new(entity_id: current_entity.id)
    
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
    
    if @landing_page.save
      redirect_to edit_landing_page_path(@landing_page), notice: 'Landing page was successfully created.'
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
  
  # Public-facing landing page view (no auth required)
  def public_view
    @landing_page = LandingPage.published.find_by!(slug: params[:slug])
    
    # Track the view
    track_landing_page_view
    
    render layout: 'landing_page', inline: ""
  rescue ActiveRecord::RecordNotFound
    render file: "#{Rails.root}/public/404.html", layout: false, status: :not_found
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
end 