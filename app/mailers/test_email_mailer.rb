class TestEmailMailer < ApplicationMailer
  # Send a test email using a specified template
  def template_test(template, contact, user)
    @template = template
    @contact = contact
    @user = user
    
    # Process the template body to replace placeholders
    @body = process_template_body(template.body, contact)
    
    mail(
      to: contact.email,
      subject: "[TEST] #{template.subject}",
      content_type: 'text/html'
    )
  end
  
  private
  
  # Replace placeholders in template with contact data
  def process_template_body(body, contact)
    body.gsub('{{first_name}}', contact.first_name)
        .gsub('{{last_name}}', contact.last_name)
        .gsub('{{email}}', contact.email)
  end
end