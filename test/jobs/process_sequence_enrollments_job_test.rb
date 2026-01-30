require 'test_helper'

class ProcessSequenceEnrollmentsJobTest < ActiveJob::TestCase
  setup do
    @entity = entities(:default)
    @sequence = email_sequences(:welcome_sequence)
    @sequence.update!(entity: @entity)
    
    # Create a fresh contact to avoid conflicts
    @contact = Contact.create!(
      entity: @entity,
      email: "process-job-test-#{SecureRandom.hex(4)}@example.com",
      first_name: "Process",
      last_name: "Test"
    )
    
    # Clean up existing enrollments and deliveries
    @sequence.sequence_email_deliveries.destroy_all
    @sequence.sequence_enrollments.destroy_all
    
    # Create a pending enrollment
    @enrollment = SequenceEnrollment.create!(
      email_sequence: @sequence,
      contact: @contact,
      entity: @entity,
      status: 'pending',
      current_step_number: 0
    )
  end

  test "should skip if sequence not found" do
    assert_nothing_raised do
      ProcessSequenceEnrollmentsJob.perform_now(999999)
    end
  end

  test "should skip if sequence is not active" do
    assert_equal 'draft', @sequence.status
    
    ProcessSequenceEnrollmentsJob.perform_now(@sequence.id)
    
    @enrollment.reload
    assert_equal 'pending', @enrollment.status
  end

  test "should activate pending enrollments when sequence is active" do
    # Activate the sequence directly
    @sequence.update!(status: 'active')
    
    ProcessSequenceEnrollmentsJob.perform_now(@sequence.id)
    
    @enrollment.reload
    assert_equal 'active', @enrollment.status
    assert_not_nil @enrollment.started_at
    assert_not_nil @enrollment.next_send_at
  end

  test "should set current_step_number to first step" do
    @sequence.update!(status: 'active')
    first_step = @sequence.sequence_steps.ordered.first
    
    ProcessSequenceEnrollmentsJob.perform_now(@sequence.id)
    
    @enrollment.reload
    assert_equal first_step.step_number, @enrollment.current_step_number
  end

  test "should calculate next_send_at based on first step delay" do
    @sequence.update!(status: 'active')
    first_step = @sequence.sequence_steps.ordered.first
    
    freeze_time do
      ProcessSequenceEnrollmentsJob.perform_now(@sequence.id)
      
      @enrollment.reload
      
      if first_step.delay_hours.zero?
        assert_equal Time.current, @enrollment.next_send_at
      else
        assert_equal Time.current + first_step.delay_hours.hours, @enrollment.next_send_at
      end
    end
  end

  test "should update sequence enrollment counts" do
    @sequence.update!(status: 'active')
    
    ProcessSequenceEnrollmentsJob.perform_now(@sequence.id)
    
    @sequence.reload
    assert_equal 1, @sequence.active_count
  end

  test "should queue SendSequenceEmailsJob when enrollments are ready" do
    @sequence.update!(status: 'active')
    
    # First step has delay_hours: 0, so enrollment will be ready immediately
    assert_enqueued_with(job: SendSequenceEmailsJob, args: [@sequence.id]) do
      ProcessSequenceEnrollmentsJob.perform_now(@sequence.id)
    end
  end
end
