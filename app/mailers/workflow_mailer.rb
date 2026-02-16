# frozen_string_literal: true

# WorkflowMailer - Sends emails triggered by automations
#
# Simple mailer for automation-triggered emails. Takes direct parameters
# (no EmailDelivery record needed like CampaignMailer).
#
# Usage:
#   WorkflowMailer.workflow_email(
#     to: "user@example.com",
#     subject: "Welcome!",
#     body: "<h1>Hi there</h1>",
#     entity_id: 1
#   ).deliver_later
#
class WorkflowMailer < ApplicationMailer
  # Send a simple email from an automation
  def workflow_email(to:, subject:, body:, entity_id:, html: true, automation_id: nil, contact_id: nil)
    @body = body
    @entity = Entity.find_by(id: entity_id)
    @contact = Contact.find_by(id: contact_id) if contact_id

    # SES tracking headers
    headers['X-SES-CONFIGURATION-SET'] = ENV['SES_CONFIGURATION_SET'] || 'agent-marketing'
    
    tags = ["type=automation"]
    tags << "automation_id=#{automation_id}" if automation_id
    tags << "contact_id=#{contact_id}" if contact_id
    headers['X-SES-MESSAGE-TAGS'] = tags.join(',')
    
    # Debug headers
    headers['X-Automation-ID'] = automation_id.to_s if automation_id

    # Use the entity's verified custom domain for from/reply-to when available
    default_from = "AMOS <#{ENV['MAILER_SENDER'] || 'noreply@amoslabs.com'}>"

    mail(
      to: to,
      subject: subject,
      from: @entity&.sending_from_header || default_from,
      reply_to: @entity&.sending_reply_to
    ) do |format|
      if html
        format.html { render html: render_html_body.html_safe }
        format.text { render plain: strip_html(@body) }
      else
        format.text { render plain: @body }
      end
    end
  end

  private

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
            <p>Sent by #{@entity&.name || 'AMOS'}</p>
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
end
