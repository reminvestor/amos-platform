class CampaignsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_campaign, only: [:show, :edit, :update, :destroy, :send_test, :schedule, :pause, :resume, :stop, :analyze]
  
  def index
    @campaigns = current_user.campaigns.order(created_at: :desc)
  end

  def show
    @email_deliveries = @campaign.email_deliveries.includes(:contact).order(sent_at: :desc)
  end

  def new
    @campaign = current_user.campaigns.new(status: 'draft')
    @contact_groups = current_user.contact_groups
    @email_templates = current_user.email_templates
  end

  def create
    @campaign = current_user.campaigns.new(campaign_params)
    
    if @campaign.save
      redirect_to campaigns_path, notice: 'Campaign was successfully created.'
    else
      @contact_groups = current_user.contact_groups
      @email_templates = current_user.email_templates
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @contact_groups = current_user.contact_groups
    @email_templates = current_user.email_templates
  end

  def update
    if @campaign.update(campaign_params)
      redirect_to campaigns_path, notice: 'Campaign was successfully updated.'
    else
      @contact_groups = current_user.contact_groups
      @email_templates = current_user.email_templates
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @campaign.destroy
    redirect_to campaigns_path, notice: 'Campaign was successfully deleted.'
  end
  
  # Campaign actions
  def send_test
    if params[:email].present? && @campaign.email_template.present?
      CampaignMailer.test_campaign_email(@campaign, params[:email]).deliver_now
      redirect_to @campaign, notice: "Test email sent to #{params[:email]}."
    else
      redirect_to @campaign, alert: "Please provide an email address and ensure a template is selected."
    end
  end
  
  def schedule
    scheduled_at = params[:scheduled_at].present? ? DateTime.parse(params[:scheduled_at]) : DateTime.now
    
    service = CampaignService.new(@campaign)
    service.schedule_campaign(scheduled_at)
    
    redirect_to @campaign, notice: "Campaign scheduled for #{scheduled_at.strftime('%b %d, %Y at %I:%M %p')}"
  end
  
  def pause
    if @campaign.update(status: 'paused')
      redirect_to @campaign, notice: 'Campaign paused successfully.'
    else
      redirect_to @campaign, alert: 'Failed to pause campaign.'
    end
  end
  
  def resume
    service = CampaignService.new(@campaign)
    service.start_campaign
    redirect_to @campaign, notice: 'Campaign resumed successfully.'
  end
  
  def stop
    if @campaign.update(status: 'stopped')
      redirect_to @campaign, notice: 'Campaign stopped successfully.'
    else
      redirect_to @campaign, alert: 'Failed to stop campaign.'
    end
  end
  
  def analyze
    # Forward to the AI content controller's analyze_campaign method
    redirect_to ai_analyze_campaign_path(@campaign)
  end
  
  private
  
  def set_campaign
    @campaign = current_user.campaigns.find(params[:id])
  end
  
  def campaign_params
    params.require(:campaign).permit(
      :name, 
      :description, 
      :status, 
      :scheduled_at,
      :email_template_id,
      contact_group_ids: []
    )
  end
end
