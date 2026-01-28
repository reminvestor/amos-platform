require 'test_helper'

class CreateEmailSequenceToolTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:default)
    @user = users(:default)
    @contact_group = contact_groups(:default_group)
    @tool = Tools::CreateObjectTool.new(
      entity: @entity,
      user: @user,
      session: nil,
      execution: nil
    )
  end

  test "creates email sequence with valid data" do
    result = @tool.execute({
      'object_type' => 'email_sequences',
      'data' => {
        'name' => 'Test Sequence',
        'goal' => 'Test goal',
        'contact_group_id' => @contact_group.id
      }
    })

    assert result[:success]
    assert_equal 'email_sequences', result[:object_type]
    assert result[:id].present?

    sequence = EmailSequence.find(result[:id])
    assert_equal 'Test Sequence', sequence.name
    assert_equal 'draft', sequence.status
    assert_equal @entity.id, sequence.entity_id
  end

  test "creates sequence step with valid data" do
    sequence = email_sequences(:welcome_sequence)

    result = @tool.execute({
      'object_type' => 'sequence_steps',
      'data' => {
        'email_sequence_id' => sequence.id,
        'step_number' => 4,
        'delay_hours' => 240,
        'subject' => 'Follow Up',
        'body' => '<p>Follow up message</p>'
      }
    })

    assert result[:success]
    assert_equal 'sequence_steps', result[:object_type]

    step = SequenceStep.find(result[:id])
    assert_equal 4, step.step_number
    assert_equal 240, step.delay_hours
    assert_equal 10.0, step.delay_in_days
  end

  test "creates sequence enrollment with valid data" do
    sequence = email_sequences(:welcome_sequence)
    contact = contacts(:one)

    result = @tool.execute({
      'object_type' => 'sequence_enrollments',
      'data' => {
        'email_sequence_id' => sequence.id,
        'contact_id' => contact.id,
        'entity_id' => @entity.id
      }
    })

    assert result[:success]
    assert_equal 'sequence_enrollments', result[:object_type]

    enrollment = SequenceEnrollment.find(result[:id])
    assert_equal 'pending', enrollment.status
    assert_equal 0, enrollment.current_step_number
  end

  test "prevents duplicate enrollment" do
    sequence = email_sequences(:active_sequence)
    contact = contacts(:one)

    # First enrollment
    first_result = @tool.execute({
      'object_type' => 'sequence_enrollments',
      'data' => {
        'email_sequence_id' => sequence.id,
        'contact_id' => contact.id,
        'entity_id' => @entity.id
      }
    })

    # Second enrollment attempt (should return existing)
    second_result = @tool.execute({
      'object_type' => 'sequence_enrollments',
      'data' => {
        'email_sequence_id' => sequence.id,
        'contact_id' => contact.id,
        'entity_id' => @entity.id
      }
    })

    assert first_result[:success]
    assert second_result[:success]
    assert_equal first_result[:id], second_result[:id]
  end

  test "returns error for invalid contact group" do
    result = @tool.execute({
      'object_type' => 'email_sequences',
      'data' => {
        'name' => 'Test Sequence',
        'contact_group_id' => 99999
      }
    })

    assert_not result[:success]
    assert_includes result[:error], 'Contact group not found'
  end

  test "returns error for invalid email sequence" do
    result = @tool.execute({
      'object_type' => 'sequence_steps',
      'data' => {
        'email_sequence_id' => 99999,
        'step_number' => 1,
        'delay_hours' => 0
      }
    })

    assert_not result[:success]
    assert_includes result[:error], 'Email sequence not found'
  end
end
