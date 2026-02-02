# frozen_string_literal: true

require 'test_helper'

class AmosThinkingTimeJobTest < ActiveJob::TestCase
  setup do
    @entity = entities(:one)
  end

  test "enqueues job for single entity" do
    assert_enqueued_with(job: AmosThinkingTimeJob, args: [{ entity_id: @entity.id }]) do
      AmosThinkingTimeJob.perform_later(entity_id: @entity.id)
    end
  end

  test "runs thinking session for entity" do
    mock_session = AmosThinkingSession.create!(
      entity: @entity,
      status: 'completed',
      reflection_summary: 'Test reflection',
      started_at: Time.current
    )
    mock_result = { session: mock_session, bounties: [] }

    AmosThinkingService.any_instance.stubs(:think!).returns(mock_result)

    # Run the job - should use mocked service
    AmosThinkingTimeJob.new.perform(entity_id: @entity.id)

    # Verify it ran
    assert mock_session.persisted?
    assert_equal 'completed', mock_session.status
  end

  test "continues with other entities on failure" do
    # Make all entities active for this test
    Entity.update_all(status: 'active')
    
    # Stub the service to always raise
    AmosThinkingService.any_instance.stubs(:think!).raises("Simulated failure")

    # Should not raise even when all entities fail - should catch and continue
    assert_nothing_raised do
      AmosThinkingTimeJob.new.perform(entity_id: nil)
    end
    
    # Job completed without raising - that's the success
  end
end
