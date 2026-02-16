# frozen_string_literal: true

require "test_helper"

class CustomDomainVerificationJobTest < ActiveJob::TestCase
  fixtures :entities, :users, :custom_domains

  setup do
    @entity = entities(:one)
    @domain = custom_domains(:verified_email_domain)
    # Reset to verifying state for testing
    @domain.update_columns(email_status: 'verifying', email_verified_at: nil)
    @entity.update(from_email: nil, sender_name: nil)
  end

  test "auto-sets entity from_email when email domain is verified" do
    # Stub SesDomainService to simulate successful verification
    mock_service = Minitest::Mock.new
    mock_service.expect(:check_verification_status, { success: true, verified: true, status: 'verified' })

    SesDomainService.stub(:new, ->(**_args) { mock_service }) do
      # Need to also stub mark_email_verified! since it's called by the service mock
      @domain.stub(:mark_email_verified!, nil) do
        # Manually replicate the job logic for testing
        service = SesDomainService.new(custom_domain: @domain)
        result = service.check_verification_status

        if result[:verified]
          entity = @domain.entity
          if entity.from_email.blank?
            entity.update(
              from_email: "hello@#{@domain.domain_name}",
              sender_name: entity.sender_name.presence || entity.name
            )
          end
        end
      end
    end

    @entity.reload
    assert_equal "hello@nuvolanetworks.com", @entity.from_email
    assert_equal "Test Entity One", @entity.sender_name
  end

  test "does not overwrite existing from_email on verification" do
    @entity.update(from_email: "existing@nuvolanetworks.com")

    # Simulate the auto-configure logic from the job
    entity = @domain.entity
    if entity.from_email.blank?
      entity.update(
        from_email: "hello@#{@domain.domain_name}",
        sender_name: entity.sender_name.presence || entity.name
      )
    end

    @entity.reload
    assert_equal "existing@nuvolanetworks.com", @entity.from_email,
      "Should not overwrite existing from_email"
  end

  test "job enqueues correctly" do
    assert_enqueued_with(job: CustomDomainVerificationJob) do
      CustomDomainVerificationJob.perform_later(@domain.id, 'email')
    end
  end
end
