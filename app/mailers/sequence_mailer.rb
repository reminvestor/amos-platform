# frozen_string_literal: true

class SequenceMailer < ApplicationMailer
  # Sends an email as part of an email sequence
  # Uses SES Configuration Sets for open/click/bounce tracking (same as CampaignMailer)
  #
  # @param delivery [SequenceEmailDelivery] The delivery record tracking this email
  #
  def sequence_email(delivery)
    @delivery = delivery
    @contact = delivery.contact
    @sequence = delivery.email_sequence
    @step = delivery.sequence_step
    @entity = delivery.entity
    
    # Get email content from step
    @subject = @step.effective_subject
    @body = @step.effective_body
    
    # Process personalization
    @body = process_template_variables(@body, @contact)
    @subject = process_template_variables(@subject, @contact)
    
    # Generate unsubscribe URL
    @unsubscribe_url = generate_unsubscribe_url(@contact)

    # Determine from address (same pattern as CampaignMailer)
    from_email = @entity.default_from_email.presence || 
                 ENV['DEFAULT_FROM_EMAIL'] || 
                 Rails.application.config.action_mailer.default_options[:from]
    from_name = @entity.name.presence || 'AMOS'

    # Set SES tracking headers (same as CampaignMailer)
    headers['X-SES-CONFIGURATION-SET'] = ENV['SES_CONFIGURATION_SET'] || 'agent-marketing'
    headers['X-SES-MESSAGE-TAGS'] = "type=sequence,sequence_id=#{@sequence.id},step_id=#{@step.id},contact_id=#{@contact.id},delivery_id=#{@delivery.id}"
    
    # Set our own headers for debugging
    headers['X-Sequence-ID'] = @sequence.id.to_s
    headers['X-Step-Number'] = @step.step_number.to_s
    headers['X-Contact-ID'] = @contact.id.to_s
    headers['X-Delivery-ID'] = @delivery.id.to_s

    mail(
      to: @contact.email,
      subject: @subject,
      from: "#{from_name} <#{from_email}>",
      reply_to: from_email
    ) do |format|
      format.html { render html: render_html_body.html_safe }
      format.text { render plain: strip_html(@body) }
    end
  end

  private

  def process_template_variables(content, contact)
    return content unless content.present? && contact.present?

    content
      .gsub(/\{\{\s*first_name\s*\}\}/, contact.first_name.to_s)
      .gsub(/\{\{\s*last_name\s*\}\}/, contact.last_name.to_s)
      .gsub(/\{\{\s*email\s*\}\}/, contact.email.to_s)
      .gsub(/\{\{\s*full_name\s*\}\}/, "#{contact.first_name} #{contact.last_name}".strip)
      .gsub(/\{\{\s*company\s*\}\}/, contact.metadata&.dig('company').to_s)
  end

  def render_html_body
    # Wrap body in basic email template if it's not already a full HTML document
    if @body.include?('<html') || @body.include?('<body')
      @body
    else
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px; }
            a { color: #3B82F6; }
            .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #eee; font-size: 12px; color: #666; }
          </style>
        </head>
        <body>
          #{@body}
          
          <div class="footer">
            <p>You're receiving this email because you subscribed to #{@entity.name}.</p>
            <p><a href="#{@unsubscribe_url}">Unsubscribe</a></p>
          </div>
        </body>
        </html>
      HTML
    end
  end

  def strip_html(html)
    html.to_s
      .gsub(/<br\s*\/?>/i, "\n")
      .gsub(/<\/p>/i, "\n\n")
      .gsub(/<[^>]+>/, '')
      .gsub(/&nbsp;/, ' ')
      .gsub(/&amp;/, '&')
      .gsub(/&lt;/, '<')
      .gsub(/&gt;/, '>')
      .strip
  end

  def generate_unsubscribe_url(contact)
    token = contact.unsubscribe_token || SecureRandom.urlsafe_base64(32)
    host = ENV['APPLICATION_HOST'] || 'app.amoslabs.com'
    
    Rails.application.routes.url_helpers.unsubscribe_url(
      token: token,
      host: host,
      protocol: 'https'
    )
  rescue
    "#"
  end
end
