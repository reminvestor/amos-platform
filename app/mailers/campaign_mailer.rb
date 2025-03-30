class CampaignMailer < ApplicationMailer
  # Send a campaign email to a contact
  def campaign_email(email_delivery)
    @email_delivery = email_delivery
    @campaign = email_delivery.campaign
    @contact = email_delivery.contact
    @email_template = email_delivery.email_template || @campaign.email_template
    
    # For tracking opens
    @tracking_pixel_url = email_open_url(email_delivery.id, host: default_url_options[:host])
    
    # Process the template body to add click tracking to links
    if @email_template.body.present? && @email_delivery.id.present?
      @email_body = add_tracking_to_links(@email_template.body, email_delivery.id)
    else
      @email_body = @email_template.body
    end
    
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
    
    # Set a dummy tracking URL for test emails
    @tracking_pixel_url = "#"
    @email_body = @email_template.body
    
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
  
  # Add tracking to links in the email content
  def add_tracking_to_links(html_content, delivery_id)
    # Use nokogiri to parse HTML
    require 'nokogiri'
    
    doc = Nokogiri::HTML(html_content)
    
    # Find all links
    doc.css('a').each do |link|
      href = link['href']
      next if href.blank? || href.start_with?('#')
      
      # Wrap the link with our tracking URL
      tracked_url = email_click_url(
        delivery_id, 
        host: default_url_options[:host],
        url: href
      )
      
      link['href'] = tracked_url
    end
    
    doc.to_html
  end
end
