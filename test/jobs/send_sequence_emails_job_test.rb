require 'test_helper'

class SendSequenceEmailsJobTest < ActiveJob::TestCase
  setup do
    @entity = entities(:default)
    @sequence = email_sequences(:active_sequence)
    @sequence.update!(entity: @entity)
    
    # Create a fresh contact to avoid enrollment conflicts
    @user = users(:one)
    @contact = Contact.create!(
      entity: @entity,
      user: @user,
      email: "send-job-test-#{SecureRandom.hex(4)}@example.com",
      first_name: "Job",
      last_name: "Test"
    )
    
    # Clean up existing steps and enrollments for this sequence
    @sequence.sequence_email_deliveries.destroy_all
    @sequence.sequence_enrollments.destroy_all
    @sequence.sequence_steps.destroy_all
    
    # Create a step
    @step = @sequence.sequence_steps.create!(
      step_number: 1,
      delay_hours: 0,
      subject: "Test Subject",
      body: "<p>Test body</p>"
    )
    
    # Create an active enrollment ready to send
    @enrollment = SequenceEnrollment.create!(
      email_sequence: @sequence,
      contact: @contact,
      entity: @entity,
      status: 'active',
      current_step_number: 1,
      started_at: 1.hour.ago,
      next_send_at: 1.minute.ago
    )
  end

  test "should process enrollments ready to send" do
    assert_enqueued_emails 1 do
      SendSequenceEmailsJob.perform_now(@sequence.id)
    end
  end

  test "should skip opted-out contacts" do
    @contact.update!(opted_out: true)
    
    assert_no_enqueued_emails do
      SendSequenceEmailsJob.perform_now(@sequence.id)
    end
    
    @enrollment.reload
    assert_equal 'cancelled', @enrollment.status
  end

  test "should advance enrollment to next step after sending" do
    next_step = @sequence.sequence_steps.create!(
      step_number: 2,
      delay_hours: 72,
      subject: "Follow up",
      body: "<p>Follow up content</p>"
    )
    
    SendSequenceEmailsJob.perform_now(@sequence.id)
    
    @enrollment.reload
    assert_equal 2, @enrollment.current_step_number
    assert @enrollment.next_send_at > Time.current
  end

  test "should complete enrollment when no more steps" do
    # Remove any other steps
    @sequence.sequence_steps.where.not(step_number: @step.step_number).destroy_all
    
    SendSequenceEmailsJob.perform_now(@sequence.id)
    
    @enrollment.reload
    assert_equal 'completed', @enrollment.status
    assert_not_nil @enrollment.completed_at
  end

  test "should increment step sent_count" do
    initial_count = @step.sent_count
    
    SendSequenceEmailsJob.perform_now(@sequence.id)
    
    @step.reload
    assert_equal initial_count + 1, @step.sent_count
  end

  test "should skip if sequence is not active" do
    @sequence.update!(status: 'paused')
    
    assert_no_enqueued_emails do
      SendSequenceEmailsJob.perform_now(@sequence.id)
    end
  end

  test "should process all sequences when no id provided" do
    # Create another active sequence with ready enrollment
    sequence2 = EmailSequence.create!(
      name: "Another Sequence",
      entity: @entity,
      contact_group: @sequence.contact_group,
      status: 'active'
    )
    
    step2 = sequence2.sequence_steps.create!(
      step_number: 1,
      delay_hours: 0,
      subject: "Test",
      body: "Test"
    )
    
    contact2 = contacts(:two)
    SequenceEnrollment.create!(
      email_sequence: sequence2,
      contact: contact2,
      entity: @entity,
      status: 'active',
      current_step_number: 1,
      next_send_at: 1.minute.ago
    )
    
    # Should send emails for both sequences
    assert_enqueued_emails 2 do
      SendSequenceEmailsJob.perform_now
    end
  end

  test "should personalize email content" do
    @contact.update!(first_name: 'John', last_name: 'Doe')
    @step.update!(
      subject: "Hello {{first_name}}",
      body: "<p>Dear {{full_name}},</p>"
    )
    
    # Just verify it doesn't error - actual personalization tested in mailer
    assert_nothing_raised do
      SendSequenceEmailsJob.perform_now(@sequence.id)
    end
  end

  test "should create activity record for sent email" do
    assert_difference 'Activity.count', 1 do
      SendSequenceEmailsJob.perform_now(@sequence.id)
    end
    
    activity = Activity.last
    assert_equal 'email_sent', activity.activity_type
    assert_equal @contact.id, activity.contact_id
  end
end
