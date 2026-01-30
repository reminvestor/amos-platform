require 'test_helper'

class SequenceEmailDeliveryTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:default)
    @sequence = email_sequences(:active_sequence)
    @step = @sequence.sequence_steps.first || @sequence.sequence_steps.create!(
      step_number: 1, delay_hours: 0, subject: "Test", body: "Test"
    )
    @contact = contacts(:one)
    @enrollment = @sequence.sequence_enrollments.find_by(contact: @contact) || 
                  @sequence.sequence_enrollments.create!(contact: @contact, entity: @entity, status: 'active')
  end

  test "should be valid with required attributes" do
    delivery = SequenceEmailDelivery.new(
      email_sequence: @sequence,
      sequence_step: @step,
      sequence_enrollment: @enrollment,
      contact: @contact,
      entity: @entity,
      status: 'pending'
    )
    assert delivery.valid?
  end

  test "should require valid status" do
    delivery = SequenceEmailDelivery.new(
      email_sequence: @sequence,
      sequence_step: @step,
      sequence_enrollment: @enrollment,
      contact: @contact,
      entity: @entity,
      status: 'invalid_status'
    )
    assert_not delivery.valid?
    assert_includes delivery.errors[:status], "is not included in the list"
  end

  test "mark_as_sent should update status and timestamp" do
    delivery = SequenceEmailDelivery.create!(
      email_sequence: @sequence,
      sequence_step: @step,
      sequence_enrollment: @enrollment,
      contact: @contact,
      entity: @entity,
      status: 'pending'
    )
    
    delivery.mark_as_sent("test-message-id")
    
    assert_equal "sent", delivery.status
    assert_not_nil delivery.sent_at
    assert_equal "test-message-id", delivery.ses_message_id
  end

  test "mark_as_opened should update status and increment step metrics" do
    delivery = SequenceEmailDelivery.create!(
      email_sequence: @sequence,
      sequence_step: @step,
      sequence_enrollment: @enrollment,
      contact: @contact,
      entity: @entity,
      status: 'delivered'
    )
    
    initial_count = @step.opened_count
    
    delivery.mark_as_opened
    
    assert_equal "opened", delivery.status
    assert_not_nil delivery.opened_at
    
    @step.reload
    assert_equal initial_count + 1, @step.opened_count
  end

  test "mark_as_opened should only count once" do
    delivery = SequenceEmailDelivery.create!(
      email_sequence: @sequence,
      sequence_step: @step,
      sequence_enrollment: @enrollment,
      contact: @contact,
      entity: @entity,
      status: 'opened',
      opened_at: 1.hour.ago
    )
    
    initial_count = @step.opened_count
    
    # Try to mark as opened again
    delivery.mark_as_opened
    
    @step.reload
    # Should not increment again
    assert_equal initial_count, @step.opened_count
  end

  test "mark_as_clicked should also mark as opened if not already" do
    delivery = SequenceEmailDelivery.create!(
      email_sequence: @sequence,
      sequence_step: @step,
      sequence_enrollment: @enrollment,
      contact: @contact,
      entity: @entity,
      status: 'delivered'
    )
    
    delivery.mark_as_clicked
    
    assert_equal "clicked", delivery.status
    assert_not_nil delivery.opened_at
    assert_not_nil delivery.clicked_at
  end

  test "mark_as_bounced should cancel enrollment and opt out contact" do
    @contact.update!(opted_out: false)
    @enrollment.update!(status: 'active')
    
    delivery = SequenceEmailDelivery.create!(
      email_sequence: @sequence,
      sequence_step: @step,
      sequence_enrollment: @enrollment,
      contact: @contact,
      entity: @entity,
      status: 'sent'
    )
    
    delivery.mark_as_bounced("Hard bounce")
    
    assert_equal "bounced", delivery.status
    assert_equal "Hard bounce", delivery.error_message
    
    @enrollment.reload
    assert_equal "cancelled", @enrollment.status
    
    @contact.reload
    assert @contact.opted_out?
  end

  test "mark_as_complaint should opt out contact and cancel enrollment" do
    @contact.update!(opted_out: false)
    @enrollment.update!(status: 'active')
    
    delivery = SequenceEmailDelivery.create!(
      email_sequence: @sequence,
      sequence_step: @step,
      sequence_enrollment: @enrollment,
      contact: @contact,
      entity: @entity,
      status: 'delivered'
    )
    
    delivery.mark_as_complaint
    
    assert_equal "failed", delivery.status
    
    @contact.reload
    assert @contact.opted_out?
    
    @enrollment.reload
    assert_equal "cancelled", @enrollment.status
  end

  test "scopes should filter correctly" do
    # Create deliveries with different statuses
    SequenceEmailDelivery.create!(
      email_sequence: @sequence, sequence_step: @step, sequence_enrollment: @enrollment,
      contact: @contact, entity: @entity, status: 'pending'
    )
    
    assert SequenceEmailDelivery.pending.exists?
    assert_not SequenceEmailDelivery.pending.where(status: 'sent').exists?
  end

  test "opened? and clicked? helpers" do
    delivery = SequenceEmailDelivery.new(status: 'sent')
    
    assert_not delivery.opened?
    assert_not delivery.clicked?
    
    delivery.opened_at = Time.current
    assert delivery.opened?
    
    delivery.clicked_at = Time.current
    assert delivery.clicked?
  end
end
