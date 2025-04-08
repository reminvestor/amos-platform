class CampaignsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_campaign, only: [:show, :edit, :update, :destroy, :send_test, :schedule, :send_now, :pause, :resume, :stop, :reactivate, :analyze, :sync_mailgun, :setup_drip, :trigger_drip]
  
  def index
    # Get all campaigns for this user
    all_campaigns = current_user.campaigns.order(created_at: :desc)
    
    # Separate into parent campaigns and follow-up campaigns
    @parent_campaigns = all_campaigns.select { |c| !c.is_follow_up? }
    @child_campaigns = all_campaigns.select { |c| c.is_follow_up? }
    
    # Group child campaigns by their parent
    @child_campaigns_by_parent = {}
    @child_campaigns.each do |child|
      parent_id = child.parent_campaigns.first&.id
      if parent_id
        @child_campaigns_by_parent[parent_id] ||= []
        @child_campaigns_by_parent[parent_id] << child
      end
    end
  end

  def show
    # Try to sync with Mailgun
    @campaign.sync_mailgun_stats
    
    # Update opted out contacts count
    if @campaign.contact_groups.any?
      contacts = @campaign.contacts
      @campaign.update(opted_out_contacts_count: contacts.where(opted_out: true).count)
    end
    
    @email_deliveries = @campaign.email_deliveries.includes(:contact).order(sent_at: :desc).page(params[:page]).per(50)
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
    begin
      scheduled_time = if params[:scheduled_at].present?
        DateTime.parse(params[:scheduled_at])
      else
        DateTime.now
      end
      
      # Log the received parameters for debugging
      Rails.logger.info("Campaign scheduling: ID=#{@campaign.id}, scheduled_at=#{scheduled_time}, raw_param=#{params[:scheduled_at]}")
      
      service = CampaignService.new(@campaign)
      service.schedule_campaign(scheduled_time)
      
      redirect_to @campaign, notice: "Campaign scheduled for #{scheduled_time.strftime('%b %d, %Y at %I:%M %p')}"
    rescue => e
      Rails.logger.error("Campaign scheduling error: #{e.message}")
      redirect_to @campaign, alert: "Error scheduling campaign: #{e.message}"
    end
  end
  
  def send_now
    begin
      if @campaign.email_template.blank?
        redirect_to @campaign, alert: "Cannot send campaign: No email template selected."
        return
      end
      
      if @campaign.contact_groups.empty?
        redirect_to @campaign, alert: "Cannot send campaign: No contact groups selected."
        return
      end
      
      # Log the action
      Rails.logger.info("Campaign sending immediately: ID=#{@campaign.id}")
      
      service = CampaignService.new(@campaign)
      service.start_campaign
      
      redirect_to @campaign, notice: "Campaign started successfully and is now sending!"
    rescue => e
      Rails.logger.error("Campaign immediate send error: #{e.message}")
      redirect_to @campaign, alert: "Error sending campaign: #{e.message}"
    end
  end
  
  def pause
    @campaign = Campaign.find(params[:id])
    service = CampaignService.new(@campaign)
    service.pause_campaign
    
    respond_to do |format|
      format.html { redirect_to campaigns_path, notice: 'Campaign was successfully paused.' }
    end
  end
  
  def resume
    @campaign = Campaign.find(params[:id])
    service = CampaignService.new(@campaign)
    service.resume_campaign
    
    respond_to do |format|
      format.html { redirect_to campaigns_path, notice: 'Campaign was successfully resumed.' }
    end
  end
  
  def stop
    @campaign = Campaign.find(params[:id])
    service = CampaignService.new(@campaign)
    service.stop_campaign
    
    respond_to do |format|
      format.html { redirect_to campaigns_path, notice: 'Campaign was successfully stopped.' }
    end
  end
  
  def reactivate
    if @campaign.status == 'stopped' || @campaign.status == 'completed'
      if @campaign.update(status: 'draft')
        redirect_to @campaign, notice: 'Campaign reactivated and set to draft status.'
      else
        redirect_to @campaign, alert: 'Failed to reactivate campaign.'
      end
    else
      redirect_to @campaign, alert: 'Only stopped or completed campaigns can be reactivated.'
    end
  end
  
  def analyze
    # Sync with Mailgun before analyzing
    @campaign.sync_mailgun_stats
    
    # Forward to the AI content controller's analyze_campaign method
    redirect_to ai_analyze_campaign_path(@campaign)
  end
  
  def sync_mailgun
    if @campaign.sync_mailgun_stats
      redirect_to @campaign, notice: "Campaign stats sync with Mailgun has been queued."
    else
      redirect_to @campaign, alert: "Unable to sync campaign with Mailgun."
    end
  end
  
  # Drip campaign methods
  def setup_drip
    # Verify campaign is eligible for drip campaigns
    unless ['in_progress', 'completed'].include?(@campaign.status)
      redirect_to @campaign, alert: "Only in-progress or completed campaigns can have drip sequences."
      return
    end
    
    # Get parameters
    delay_days = params[:delay_days].to_i
    condition = params[:condition] || 'not_opened'
    subject_prefix = params[:subject_prefix] || '[Reminder] '
    
    # Validate parameters
    if delay_days < 1 
      delay_days = 3 # Default to 3 days if invalid
    end
    
    # Create the drip follow-up
    drip_campaign = @campaign.create_drip_follow_up(
      delay_days: delay_days,
      condition: condition,
      subject_prefix: subject_prefix
    )
    
    if drip_campaign
      redirect_to @campaign, notice: "Drip campaign sequence created! The follow-up will be sent #{delay_days} days after the campaign completes."
    else
      redirect_to @campaign, alert: "Failed to create drip campaign sequence: #{@campaign.errors.full_messages.join(', ')}"
    end
  end
  
  def trigger_drip
    # Find the specified drip campaign
    drip = DrippedCampaign.find_by(id: params[:drip_id], original_campaign_id: @campaign.id)
    
    unless drip
      redirect_to @campaign, alert: "Drip campaign not found."
      return
    end
    
    # Create the follow-up campaign immediately
    new_campaign = drip.create_next_follow_up!
    
    if new_campaign
      # Mark the drip as processed
      drip.update(active: false)
      
      redirect_to new_campaign, notice: "Follow-up campaign created successfully! You can now review and send it."
    else
      redirect_to @campaign, alert: "Unable to create follow-up campaign. There may be no contacts matching the condition."
    end
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
