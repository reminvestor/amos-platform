require 'test_helper'

class SequenceEnrollmentTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:default)
    @sequence = email_sequences(:welcome_sequence)
    @contact = contacts(:one)
    @enrollment = sequence_enrollments(:pending_enrollment)
  end

  test "should be valid with required attributes" do
    enrollment = SequenceEnrollment.new(
      email_sequence: @sequence,
      contact: @contact,
      entity: @entity,
      status: "pending"
    )
    assert enrollment.valid?
  end

  test "should prevent duplicate enrollments" do
    duplicate = SequenceEnrollment.new(
      email_sequence: @enrollment.email_sequence,
      contact: @enrollment.contact,
      entity: @entity,
      status: "pending"
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:contact_id], "is already enrolled in this sequence"
  end

  test "start should change status to active" do
    assert @enrollment.start!
    assert_equal "active", @enrollment.status
    assert @enrollment.started_at.present?
    assert @enrollment.next_send_at.present?
  end

  test "complete should change status to completed" do
    enrollment = sequence_enrollments(:active_enrollment)
    assert enrollment.complete!
    assert_equal "completed", enrollment.status
    assert enrollment.completed_at.present?
    assert_nil enrollment.next_send_at
  end

  test "pause should change status to paused" do
    enrollment = sequence_enrollments(:active_enrollment)
    assert enrollment.pause!
    assert_equal "paused", enrollment.status
  end

  test "cancel should change status to cancelled" do
    enrollment = sequence_enrollments(:active_enrollment)
    assert enrollment.cancel!
    assert_equal "cancelled", enrollment.status
    assert_nil enrollment.next_send_at
  end

  test "advance_to_next_step should increment step number" do
    # Create steps for the sequence
    @sequence.sequence_steps.create!(
      step_number: 1,
      delay_hours: 0,
      subject: "Step 1",
      body: "Body 1"
    )
    @sequence.sequence_steps.create!(
      step_number: 2,
      delay_hours: 72,
      subject: "Step 2",
      body: "Body 2"
    )

    @enrollment.update!(current_step_number: 1, status: 'active')
    @enrollment.advance_to_next_step!

    assert_equal 2, @enrollment.current_step_number
    assert @enrollment.next_send_at > Time.current
  end

  test "advance_to_next_step should complete when no more steps" do
    @enrollment.update!(current_step_number: 3, status: 'active')
    @enrollment.advance_to_next_step!

    assert_equal "completed", @enrollment.status
    assert @enrollment.completed_at.present?
  end

  test "should calculate progress percentage correctly" do
    # Create 4 steps
    (1..4).each do |i|
      @sequence.sequence_steps.create!(
        step_number: i,
        delay_hours: i * 24,
        subject: "Step #{i}",
        body: "Body #{i}"
      )
    end

    @enrollment.update!(current_step_number: 2)
    assert_equal 50.0, @enrollment.progress_percentage

    @enrollment.update!(current_step_number: 4)
    assert_equal 100.0, @enrollment.progress_percentage
  end
end
