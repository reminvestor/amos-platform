require 'test_helper'

class UpdateEmailSequenceToolTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:default)
    @user = users(:default)
    @tool = Tools::UpdateObjectTool.new(
      entity: @entity,
      user: @user,
      session: nil,
      execution: nil
    )
  end

  test "updates email sequence basic fields" do
    sequence = email_sequences(:welcome_sequence)

    result = @tool.execute({
      'object_type' => 'email_sequence',
      'id' => sequence.id,
      'data' => {
        'name' => 'Updated Sequence Name',
        'goal' => 'Updated goal'
      }
    })

    assert result[:success]
    sequence.reload
    assert_equal 'Updated Sequence Name', sequence.name
    assert_equal 'Updated goal', sequence.goal
  end

  test "activates email sequence" do
    sequence = email_sequences(:welcome_sequence)
    # Add at least one step (required for activation)
    sequence.sequence_steps.create!(
      step_number: 1,
      delay_hours: 0,
      subject: 'Test',
      body: 'Test'
    )

    result = @tool.execute({
      'object_type' => 'email_sequence',
      'id' => sequence.id,
      'data' => {
        'status' => 'active'
      }
    })

    assert result[:success]
    sequence.reload
    assert_equal 'active', sequence.status
  end

  test "pauses active sequence" do
    sequence = email_sequences(:active_sequence)

    result = @tool.execute({
      'object_type' => 'email_sequence',
      'id' => sequence.id,
      'data' => {
        'status' => 'paused'
      }
    })

    assert result[:success]
    sequence.reload
    assert_equal 'paused', sequence.status
  end

  test "enrolls contacts via update" do
    sequence = email_sequences(:welcome_sequence)
    initial_count = sequence.sequence_enrollments.count

    result = @tool.execute({
      'object_type' => 'email_sequence',
      'id' => sequence.id,
      'data' => {
        'enroll_contacts' => true
      }
    })

    assert result[:success]
    sequence.reload
    assert sequence.sequence_enrollments.count > initial_count
  end

  test "updates sequence step" do
    step = sequence_steps(:welcome_step_1)

    result = @tool.execute({
      'object_type' => 'sequence_step',
      'id' => step.id,
      'data' => {
        'subject' => 'Updated Subject',
        'delay_hours' => 24
      }
    })

    assert result[:success]
    step.reload
    assert_equal 'Updated Subject', step.subject
    assert_equal 24, step.delay_hours
  end

  test "updates sequence enrollment status" do
    enrollment = sequence_enrollments(:pending_enrollment)

    result = @tool.execute({
      'object_type' => 'sequence_enrollment',
      'id' => enrollment.id,
      'data' => {
        'action' => 'start'
      }
    })

    assert result[:success]
    enrollment.reload
    assert_equal 'active', enrollment.status
    assert enrollment.started_at.present?
  end

  test "pauses enrollment" do
    enrollment = sequence_enrollments(:active_enrollment)

    result = @tool.execute({
      'object_type' => 'sequence_enrollment',
      'id' => enrollment.id,
      'data' => {
        'action' => 'pause'
      }
    })

    assert result[:success]
    enrollment.reload
    assert_equal 'paused', enrollment.status
  end

  test "cancels enrollment" do
    enrollment = sequence_enrollments(:active_enrollment)

    result = @tool.execute({
      'object_type' => 'sequence_enrollment',
      'id' => enrollment.id,
      'data' => {
        'action' => 'cancel'
      }
    })

    assert result[:success]
    enrollment.reload
    assert_equal 'cancelled', enrollment.status
    assert_nil enrollment.next_send_at
  end
end
