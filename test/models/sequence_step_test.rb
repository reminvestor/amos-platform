require 'test_helper'

class SequenceStepTest < ActiveSupport::TestCase
  setup do
    @sequence = email_sequences(:welcome_sequence)
    @step = sequence_steps(:welcome_step_1)
  end

  test "should be valid with required attributes" do
    step = SequenceStep.new(
      email_sequence: @sequence,
      step_number: 5,
      delay_hours: 24,
      subject: "Test",
      body: "Test content"
    )
    assert step.valid?
  end

  test "should require step_number" do
    step = SequenceStep.new(
      email_sequence: @sequence,
      delay_hours: 0,
      subject: "Test",
      body: "Test"
    )
    assert_not step.valid?
    assert_includes step.errors[:step_number], "can't be blank"
  end

  test "delay_hours defaults to 0 and is valid" do
    step = SequenceStep.new(
      email_sequence: @sequence,
      step_number: 99,  # Use unique step number to avoid fixture conflicts
      subject: "Test",
      body: "Test"
    )
    # delay_hours defaults to 0, so this should be valid
    assert step.valid?, "Step should be valid with default delay_hours: #{step.errors.full_messages.join(', ')}"
  end

  test "should enforce unique step_number per sequence" do
    duplicate_step = SequenceStep.new(
      email_sequence: @sequence,
      step_number: @step.step_number,
      delay_hours: 0,
      subject: "Test",
      body: "Test"
    )
    assert_not duplicate_step.valid?
    assert_includes duplicate_step.errors[:step_number], "has already been taken"
  end

  test "should require either template or subject and body" do
    step = SequenceStep.new(
      email_sequence: @sequence,
      step_number: 10,
      delay_hours: 0
    )
    assert_not step.valid?
    assert_includes step.errors[:base], "Must have either an email template or both subject and body"
  end

  test "should calculate delay_in_days correctly" do
    step = SequenceStep.new(delay_hours: 72)
    assert_equal 3.0, step.delay_in_days

    step.delay_hours = 48
    assert_equal 2.0, step.delay_in_days
  end

  test "should calculate metrics correctly" do
    @step.update!(
      sent_count: 100,
      opened_count: 50,
      clicked_count: 20
    )

    assert_equal 50.0, @step.open_rate
    assert_equal 20.0, @step.click_rate
  end
end
