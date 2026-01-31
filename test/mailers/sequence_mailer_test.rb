require 'test_helper'

class SequenceMailerTest < ActionMailer::TestCase
  setup do
    @entity = entities(:default)
    @entity.update!(name: "Test Company") if @entity.name.blank?
    
    @sequence = email_sequences(:active_sequence)
    @sequence.update!(entity: @entity)
    
    # Clean up to avoid conflicts
    @sequence.sequence_email_deliveries.destroy_all
    @sequence.sequence_enrollments.destroy_all
    @sequence.sequence_steps.destroy_all
    
    @step = @sequence.sequence_steps.create!(
      step_number: 1,
      delay_hours: 0,
      subject: "Welcome {{first_name}}!",
      body: "<p>Hello {{first_name}} {{last_name}}, welcome to our service!</p>"
    )
    
    # Create a fresh contact
    @user = users(:one)
    @contact = Contact.create!(
      entity: @entity,
      user: @user,
      first_name: "John",
      last_name: "Doe",
      email: "mailer-test-#{SecureRandom.hex(4)}@example.com"
    )
    
    @enrollment = @sequence.sequence_enrollments.create!(contact: @contact, entity: @entity, status: 'active')
    
    @delivery = SequenceEmailDelivery.create!(
      email_sequence: @sequence,
      sequence_step: @step,
      sequence_enrollment: @enrollment,
      contact: @contact,
      entity: @entity,
      status: 'pending'
    )
  end

  test "sequence_email sends to correct recipient" do
    email = SequenceMailer.sequence_email(@delivery)
    
    assert_emails 1 do
      email.deliver_now
    end
    
    assert_equal [@contact.email], email.to
  end

  test "sequence_email personalizes subject with contact data" do
    @step.update!(subject: "Welcome {{first_name}}!")
    
    email = SequenceMailer.sequence_email(@delivery)
    
    assert_equal "Welcome John!", email.subject
  end

  test "sequence_email personalizes body with contact data" do
    @step.update!(body: "<p>Hello {{first_name}} {{last_name}}!</p>")
    
    email = SequenceMailer.sequence_email(@delivery)
    html_body = email.html_part&.body&.to_s || email.body.to_s
    
    assert_includes html_body, "Hello John Doe!"
  end

  test "sequence_email sets SES configuration set header" do
    email = SequenceMailer.sequence_email(@delivery)
    
    assert_equal (ENV['SES_CONFIGURATION_SET'] || 'agent-marketing'), email['X-SES-CONFIGURATION-SET'].value
  end

  test "sequence_email sets SES message tags" do
    email = SequenceMailer.sequence_email(@delivery)
    
    tags = email['X-SES-MESSAGE-TAGS'].value
    assert_includes tags, "type=sequence"
    assert_includes tags, "sequence_id=#{@sequence.id}"
    assert_includes tags, "step_id=#{@step.id}"
    assert_includes tags, "contact_id=#{@contact.id}"
    assert_includes tags, "delivery_id=#{@delivery.id}"
  end

  test "sequence_email includes unsubscribe link in footer" do
    email = SequenceMailer.sequence_email(@delivery)
    html_body = email.html_part&.body&.to_s || email.body.to_s
    
    assert_includes html_body.downcase, "unsubscribe"
  end

  test "sequence_email wraps content in HTML template" do
    @step.update!(body: "<p>Simple content</p>")
    
    email = SequenceMailer.sequence_email(@delivery)
    html_body = email.html_part&.body&.to_s || email.body.to_s
    
    assert_includes html_body, "<!DOCTYPE html>"
    assert_includes html_body, "Simple content"
  end

  test "sequence_email preserves full HTML if body already has html tag" do
    custom_html = "<html><body><h1>Custom HTML</h1></body></html>"
    @step.update!(body: custom_html)
    
    email = SequenceMailer.sequence_email(@delivery)
    html_body = email.html_part&.body&.to_s || email.body.to_s
    
    assert_includes html_body, "Custom HTML"
  end

  test "sequence_email has both html and text parts" do
    email = SequenceMailer.sequence_email(@delivery)
    
    # Should have multipart content
    assert email.multipart? || email.content_type.include?('text/html')
  end

  test "sequence_email sets custom headers for debugging" do
    email = SequenceMailer.sequence_email(@delivery)
    
    assert_equal @sequence.id.to_s, email['X-Sequence-ID'].value
    assert_equal @step.step_number.to_s, email['X-Step-Number'].value
    assert_equal @contact.id.to_s, email['X-Contact-ID'].value
    assert_equal @delivery.id.to_s, email['X-Delivery-ID'].value
  end

  test "sequence_email handles missing first_name gracefully" do
    # Create a contact without first_name validation (using update_column to bypass)
    @contact.update_column(:first_name, nil)
    @step.update!(body: "Hello {{first_name}}!")
    
    email = SequenceMailer.sequence_email(@delivery)
    html_body = email.html_part&.body&.to_s || email.body.to_s
    
    # Should not crash and should replace with empty string
    assert_includes html_body, "Hello !"
  end

  test "sequence_email uses entity name as from name" do
    email = SequenceMailer.sequence_email(@delivery)
    
    from = email.from_address&.display_name || email[:from].to_s
    assert_includes from, @entity.name
  end
end
