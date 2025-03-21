class CampaignMailer < ApplicationMailer
  # Send a campaign email to a contact
  def campaign_email(email_delivery)
    @email_delivery = email_delivery
    @campaign = email_delivery.campaign
    @contact = email_delivery.contact
    @email_template = email_delivery.email_template || @campaign.email_template
    
    # For tracking opens and clicks
    @tracking_pixel_url = email_delivery_open_url(email_delivery)
    
    # Set mail headers
    headers['X-Campaign-ID'] = @campaign.id.to_s
    headers['X-Contact-ID'] = @contact.id.to_s
    
    mail(
      to: @contact.email,
      subject: @email_template.subject,
      template_name: 'campaign_email'
    )
  end
  
  # Send a test email for a campaign
  def test_campaign_email(campaign, email)
    @campaign = campaign
    @email_template = campaign.email_template
    @contact = OpenStruct.new(first_name: 'Test', last_name: 'User', email: email)
    
    # Set test headers
    headers['X-Test-Email'] = 'true'
    headers['X-Campaign-ID'] = @campaign.id.to_s
    
    mail(
      to: email,
      subject: "[TEST] #{@email_template.subject}",
      template_name: 'campaign_email'
    )
  end
  
  private
  
  # Generate URL for tracking email opens
  def email_delivery_open_url(email_delivery)
    email_open_url(email_delivery.id, host: ActionMailer::Base.default_url_options[:host])
  end
end
