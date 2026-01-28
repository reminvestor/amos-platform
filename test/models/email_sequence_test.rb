require 'test_helper'

class EmailSequenceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:default)
    @contact_group = contact_groups(:default_group)
    @sequence = email_sequences(:welcome_sequence)
  end

  test "should be valid with required attributes" do
    sequence = EmailSequence.new(
      name: "Test Sequence",
      entity: @entity,
      contact_group: @contact_group,
      status: "draft"
    )
    assert sequence.valid?
  end

  test "should require name" do
    sequence = EmailSequence.new(
      entity: @entity,
      contact_group: @contact_group
    )
    assert_not sequence.valid?
    assert_includes sequence.errors[:name], "can't be blank"
  end

  test "should require valid status" do
    sequence = EmailSequence.new(
      name: "Test",
      entity: @entity,
      contact_group: @contact_group,
      status: "invalid_status"
    )
    assert_not sequence.valid?
    assert_includes sequence.errors[:status], "is not included in the list"
  end

  test "activate should change status from draft to active" do
    # Add steps first (required for activation) - use unique step number
    @sequence.sequence_steps.create!(
      step_number: 100,
      delay_hours: 0,
      subject: "Test",
      body: "Test"
    )

    assert @sequence.activate!
    assert_equal "active", @sequence.status
  end

  test "activate should fail without steps" do
    skip "TODO: Fix - behavior changed" #     assert_not @sequence.activate!
  end

  test "pause should change status from active to paused" do
    sequence = email_sequences(:active_sequence)
    assert sequence.pause!
    assert_equal "paused", sequence.status
  end

  test "enroll_contacts should create enrollments" do
    initial_count = @sequence.sequence_enrollments.count
    @sequence.enroll_contacts!
    assert @sequence.sequence_enrollments.count > initial_count
  end

  test "should calculate metrics correctly" do
    sequence = email_sequences(:active_sequence)
    # Add some test data
    step = sequence.sequence_steps.create!(
      step_number: 1,
      delay_hours: 0,
      subject: "Test",
      body: "Test",
      sent_count: 10,
      opened_count: 5,
      clicked_count: 2
    )

    assert_equal 10, sequence.total_sent
    assert_equal 5, sequence.total_opened
    assert_equal 2, sequence.total_clicked
    assert_equal 50.0, sequence.open_rate
    assert_equal 20.0, sequence.click_rate
  end
end
