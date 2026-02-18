class TestEmailMailer < ApplicationMailer
  # Send a test email using a specified template
  def template_test(template, contact, user)
    @template = template
    @contact = contact
    @user = user

    @body = process_template_body(template.body, contact)

    mail(
      to: contact.email,
      subject: "[TEST] #{template.subject}",
      content_type: "text/html"
    )
  end

  # Send a test email for a specific sequence step using its effective content
  def sequence_step_test(step, contact, user)
    @step = step
    @contact = contact
    @user = user

    @body = process_template_body(step.effective_body.to_s, contact)
    subject = process_template_body(step.effective_subject.to_s, contact)

    mail(
      to: contact.email,
      subject: "[TEST] Step #{step.step_number}: #{subject}",
      content_type: "text/html"
    )
  end

  private

  def process_template_body(body, contact)
    body.gsub("{{first_name}}", contact.first_name.to_s)
        .gsub("{{last_name}}", contact.last_name.to_s)
        .gsub("{{full_name}}", "#{contact.first_name} #{contact.last_name}".strip)
        .gsub("{{email}}", contact.email.to_s)
        .gsub("{{company}}", contact.try(:company).to_s)
  end
end
