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
    mock_reflection = {
      reflection_summary: 'Test reflection',
      observations: [],
      priorities: [],
      bounty_ideas: []
    }.to_json

    AmosThinkingService.any_instance.stub(:call_llm, ->(_) { mock_reflection }) do
      BountyIntegrationService.any_instance.stub(:sync_all!, -> { { from_tickets: [], from_goals: [], from_anomalies: [], from_features: [] } }) do
        result = nil

        assert_difference 'AmosThinkingSession.count', 1 do
          # Run the job
          AmosThinkingTimeJob.new.perform(entity_id: @entity.id)
        end

        session = AmosThinkingSession.last
        assert_equal @entity, session.entity
        assert_equal 'completed', session.status
      end
    end
  end

  test "continues with other entities on failure" do
    entity_two = entities(:two)

    # First entity fails, second should still run
    call_count = 0

    AmosThinkingService.any_instance.stub(:think!, -> {
      call_count += 1
      raise "Simulated failure" if call_count == 1
      { session: AmosThinkingSession.new, bounties: [] }
    }) do
      # Should not raise, should continue
      assert_nothing_raised do
        AmosThinkingTimeJob.new.perform(entity_id: nil)
      end
    end
  end
end
