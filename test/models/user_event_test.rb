require "test_helper"

class UserEventTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @another_entity = entities(:another_entity)
  end

  # === Validations ===

  test "valid event with all required fields" do
    event = UserEvent.new(
      user: @user,
      entity: @entity,
      event_name: "test.event",
      event_category: "feature"
    )
    assert event.valid?
  end

  test "requires event_name" do
    event = UserEvent.new(event_category: "feature")
    assert_not event.valid?
    assert_includes event.errors[:event_name], "can't be blank"
  end

  test "requires event_category" do
    event = UserEvent.new(event_name: "test.event")
    assert_not event.valid?
    assert_includes event.errors[:event_category], "can't be blank"
  end

  test "validates event_category inclusion" do
    event = UserEvent.new(event_name: "test.event", event_category: "invalid")
    assert_not event.valid?
    assert_includes event.errors[:event_category], "is not included in the list"
  end

  test "accepts all valid categories" do
    %w[onboarding navigation feature conversion billing].each do |category|
      event = UserEvent.new(
        user: @user,
        entity: @entity,
        event_name: "test.event",
        event_category: category
      )
      assert event.valid?, "Expected category '#{category}' to be valid"
    end
  end

  # === Scopes ===

  test "for_category scope filters by category" do
    assert UserEvent.for_category("onboarding").count >= 2
    assert UserEvent.for_category("feature").count >= 1
  end

  test "for_event scope filters by event name" do
    results = UserEvent.for_event("onboarding.started")
    assert results.count >= 1
  end

  # === conversion_rate (entity-scoped) ===

  test "conversion_rate calculates rate between two events" do
    rate = UserEvent.conversion_rate(
      "onboarding.started",
      "onboarding.completed",
      entity: @entity
    )
    assert_equal 100.0, rate
  end

  test "conversion_rate returns 0 when no from_events exist" do
    rate = UserEvent.conversion_rate(
      "nonexistent.event",
      "onboarding.completed",
      entity: @entity
    )
    assert_equal 0.0, rate
  end

  test "conversion_rate is scoped to entity" do
    # another_entity has onboarding.started but not onboarding.completed
    rate = UserEvent.conversion_rate(
      "onboarding.started",
      "onboarding.completed",
      entity: @another_entity
    )
    assert_equal 0.0, rate
  end

  # === by_cohort (entity-scoped) ===

  test "by_cohort scopes by entity and date range" do
    results = UserEvent.by_cohort(
      entity: @entity,
      start_date: 10.days.ago,
      end_date: Time.current
    )
    assert results.count >= 3
    assert results.all? { |e| e.entity_id == @entity.id }
  end

  test "by_cohort excludes other entities" do
    results = UserEvent.by_cohort(
      entity: @entity,
      start_date: 10.days.ago,
      end_date: Time.current
    )
    assert_not results.any? { |e| e.entity_id == @another_entity.id }
  end
end
