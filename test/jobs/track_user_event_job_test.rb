require "test_helper"

class TrackUserEventJobTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @entity = entities(:one)
  end

  test "creates a user event" do
    assert_difference "UserEvent.count", 1 do
      TrackUserEventJob.perform_now(
        user_id: @user.id,
        entity_id: @entity.id,
        event_name: "test.event",
        event_category: "feature",
        properties: { key: "value" }
      )
    end

    event = UserEvent.last
    assert_equal @user.id, event.user_id
    assert_equal @entity.id, event.entity_id
    assert_equal "test.event", event.event_name
    assert_equal "feature", event.event_category
  end

  test "stores optional session_id and referrer" do
    TrackUserEventJob.perform_now(
      user_id: @user.id,
      entity_id: @entity.id,
      event_name: "nav.page_view",
      event_category: "navigation",
      session_id: "abc123",
      referrer: "https://example.com",
      user_agent: "TestBot/1.0"
    )

    event = UserEvent.last
    assert_equal "abc123", event.session_id
    assert_equal "https://example.com", event.referrer
    assert_equal "TestBot/1.0", event.user_agent
  end

  test "discards on invalid record" do
    # Invalid category should be discarded, not retried
    assert_nothing_raised do
      TrackUserEventJob.perform_now(
        user_id: @user.id,
        entity_id: @entity.id,
        event_name: "test.event",
        event_category: "invalid_category"
      )
    end
  end
end
