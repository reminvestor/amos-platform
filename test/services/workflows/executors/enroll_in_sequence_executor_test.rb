require 'test_helper'

class EnrollInSequenceExecutorTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:default)
    @user = users(:one)
    @sequence = email_sequences(:welcome_sequence)
    @sequence.update!(entity: @entity)
    
    # Create a fresh contact to avoid conflicts
    @user = users(:one)
    @contact = Contact.create!(
      entity: @entity,
      user: @user,
      email: "enroll-test-#{SecureRandom.hex(4)}@example.com",
      first_name: "Enroll",
      last_name: "Test"
    )
    
    # Clean up any existing deliveries and enrollments (in correct order for FK constraints)
    @sequence.sequence_email_deliveries.destroy_all
    @sequence.sequence_enrollments.destroy_all
  end

  def build_executor(config: {}, inputs: {})
    step = {
      'step_id' => 'test_step',
      'type' => 'enroll_in_sequence',
      'config' => config
    }
    
    execution = OpenStruct.new(
      entity: @entity,
      user: @user,
      workflow_context: {},
      id: 1
    )
    
    Workflows::Executors::EnrollInSequenceExecutor.new(
      step: step,
      config: config,
      inputs: inputs,
      context: {},
      execution: execution
    )
  end

  test "should enroll contact in sequence" do
    executor = build_executor(
      config: { email_sequence_id: @sequence.id },
      inputs: { contact_id: @contact.id }
    )
    
    result = executor.execute
    
    assert result[:success]
    assert result[:enrolled]
    assert_not_nil result[:enrollment_id]
    
    enrollment = SequenceEnrollment.find(result[:enrollment_id])
    assert_equal @contact.id, enrollment.contact_id
    assert_equal @sequence.id, enrollment.email_sequence_id
  end

  test "should set pending status for draft sequence" do
    assert_equal 'draft', @sequence.status
    
    executor = build_executor(
      config: { email_sequence_id: @sequence.id },
      inputs: { contact_id: @contact.id }
    )
    
    result = executor.execute
    
    enrollment = SequenceEnrollment.find(result[:enrollment_id])
    assert_equal 'pending', enrollment.status
  end

  test "should set active status and schedule for active sequence" do
    @sequence.update!(status: 'active')
    
    executor = build_executor(
      config: { email_sequence_id: @sequence.id },
      inputs: { contact_id: @contact.id }
    )
    
    result = executor.execute
    
    enrollment = SequenceEnrollment.find(result[:enrollment_id])
    assert_equal 'active', enrollment.status
    assert_not_nil enrollment.started_at
    assert_not_nil enrollment.next_send_at
  end

  test "should report already enrolled when duplicate" do
    # First enrollment
    @sequence.sequence_enrollments.create!(
      contact: @contact,
      entity: @entity,
      status: 'active'
    )
    
    executor = build_executor(
      config: { email_sequence_id: @sequence.id },
      inputs: { contact_id: @contact.id }
    )
    
    result = executor.execute
    
    assert result[:success]
    assert_not result[:enrolled]
    assert result[:already_enrolled]
  end

  test "should fail with missing sequence_id" do
    executor = build_executor(
      config: {},
      inputs: { contact_id: @contact.id }
    )
    
    result = executor.execute
    
    assert_not result[:success]
    assert_includes result[:error], "sequence ID is required"
  end

  test "should fail with missing contact_id" do
    executor = build_executor(
      config: { email_sequence_id: @sequence.id },
      inputs: {}
    )
    
    result = executor.execute
    
    assert_not result[:success]
    assert_includes result[:error], "Contact ID is required"
  end

  test "should fail when sequence not found" do
    executor = build_executor(
      config: { email_sequence_id: 999999 },
      inputs: { contact_id: @contact.id }
    )
    
    result = executor.execute
    
    assert_not result[:success]
    assert_includes result[:error], "not found"
  end

  test "should fail when contact not found" do
    executor = build_executor(
      config: { email_sequence_id: @sequence.id },
      inputs: { contact_id: 999999 }
    )
    
    result = executor.execute
    
    assert_not result[:success]
    assert_includes result[:error], "not found"
  end

  test "should update sequence enrollment counts" do
    executor = build_executor(
      config: { email_sequence_id: @sequence.id },
      inputs: { contact_id: @contact.id }
    )
    
    executor.execute
    
    @sequence.reload
    assert_equal 1, @sequence.enrolled_count
  end
end
