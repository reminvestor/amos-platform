class CampaignMailer < ApplicationMailer
  # Send a campaign email to a contact
  def campaign_email(email_delivery)
    @email_delivery = email_delivery
    @campaign = email_delivery.campaign
    @contact = email_delivery.contact
    @email_template = email_delivery.email_template || @campaign.email_template

    # For tracking opens - ensure full URL with app subdomain
    # APPLICATION_HOST is already set to app.amoslabs.com in production
    host = ENV['APPLICATION_HOST'] || 'app.amoslabs.com'
    @tracking_pixel_url = email_open_url(
      email_delivery.id,
      host: host,
      protocol: "https"
    )

    # Process template variables
    if @email_template.body.present?
      @email_body = process_template_variables(@email_template.body, @contact)
      
      # Note: With SES, we can either use SES's open/click tracking (Configuration Sets)
      # OR we can use our own manually injected tracking links.
      # Since we want control and to ensure stats are "right", let's stick to SES's tracking
      # which is more robust, but we need to ensure the Configuration Set is applied.
    else
      @email_body = @email_template.body
    end

    # Set mail headers
    headers["X-Campaign-ID"] = @campaign.id.to_s
    headers["X-Contact-ID"] = @contact.id.to_s
    
    # Set SES Configuration Set
    # This tells SES to track events for this email
    headers["X-SES-CONFIGURATION-SET"] = ENV["SES_CONFIGURATION_SET"] || "agent-marketing"
    
    # Add tags for SES event filtering
    headers["X-SES-MESSAGE-TAGS"] = "campaign_id=#{@campaign.id},contact_id=#{@contact.id}"

    # Use the entity's verified custom domain for from/reply-to when available
    @entity = @campaign.entity

    mail(
      to: @contact.email,
      subject: @email_template.subject,
      from: @entity.sending_from_header,
      reply_to: @entity.sending_reply_to,
      template_name: "campaign_email"
    )
  end

  # Send a test email for a campaign
  def test_campaign_email(campaign, email)
    @campaign = campaign
    @email_template = campaign.email_template
    @contact = OpenStruct.new(first_name: "Test", last_name: "User", email: email)

    # Set a dummy tracking URL for test emails
    @tracking_pixel_url = "#"

    # Process the template content to replace variables
    if @email_template.body.present?
      @email_body = process_template_variables(@email_template.body, @contact)
    else
      @email_body = @email_template.body
    end

    # Set test headers
    headers["X-Test-Email"] = "true"
    headers["X-Campaign-ID"] = @campaign.id.to_s
    headers["X-SES-CONFIGURATION-SET"] = ENV["SES_CONFIGURATION_SET"] || "agent-marketing"
    headers["X-SES-MESSAGE-TAGS"] = "type=test,campaign_id=#{@campaign.id}"

    # Use the entity's verified custom domain for from/reply-to when available
    @entity = @campaign.entity

    mail(
      to: email,
      subject: "[TEST] #{@email_template.subject}",
      from: @entity.sending_from_header,
      reply_to: @entity.sending_reply_to,
      template_name: "campaign_email"
    )
  end

  private

  # Process template variables like {{first_name}}
  def process_template_variables(content, contact)
    return content unless content.present? && contact.present?

    # Replace common contact variables
    content = content.gsub(/\{\{\s*first_name\s*\}\}/, contact.first_name.to_s)
    content = content.gsub(/\{\{\s*last_name\s*\}\}/, contact.last_name.to_s)
    content = content.gsub(/\{\{\s*email\s*\}\}/, contact.email.to_s)
    content = content.gsub(/\{\{\s*full_name\s*\}\}/, "#{contact.first_name} #{contact.last_name}".strip)

    # Add more variables as needed

    content
  end
end
