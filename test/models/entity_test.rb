require "test_helper"

class EntityTest < ActiveSupport::TestCase
  test "entity has stripe billing fields" do
    entity = entities(:one)

    entity.stripe_customer_id = "cus_test123"
    entity.stripe_subscription_id = "sub_test123"
    entity.subscription_status = "active"
    entity.trial_ends_at = 7.days.from_now
    entity.current_period_end = 1.month.from_now
    entity.token_usage = 50_000
    entity.token_limit = 100_000
    entity.plan_tier = "professional"

    assert entity.save
    assert_equal "cus_test123", entity.stripe_customer_id
    assert_equal "sub_test123", entity.stripe_subscription_id
    assert_equal "active", entity.subscription_status
    assert_equal 50_000, entity.token_usage
    assert_equal 100_000, entity.token_limit
    assert_equal "professional", entity.plan_tier
  end

  test "token_usage defaults to zero" do
    entity = Entity.new(
      name: "Test Entity",
      subdomain: "test-entity",
      slug: "test-entity",
      status: "active"
    )

    entity.save!
    assert_equal 0, entity.token_usage
  end

  test "subscription status can be trial, active, past_due, cancelled, or incomplete" do
    entity = entities(:one)

    ["trial", "active", "past_due", "cancelled", "incomplete"].each do |status|
      entity.subscription_status = status
      assert entity.save, "Should allow subscription_status: #{status}"
    end
  end

  test "plan tier can be starter, professional, or enterprise" do
    entity = entities(:one)

    ["starter", "professional", "enterprise"].each do |tier|
      entity.plan_tier = tier
      assert entity.save, "Should allow plan_tier: #{tier}"
    end
  end

  test "stripe fields are optional" do
    entity = Entity.new(
      name: "New Entity",
      subdomain: "new-entity",
      slug: "new-entity",
      status: "active"
    )

    assert entity.save
    assert_nil entity.stripe_customer_id
    assert_nil entity.stripe_subscription_id
    assert_equal 'inactive', entity.subscription_status
  end

  test "can query entities by subscription status" do
    entity1 = entities(:one)
    entity2 = entities(:two)

    entity1.update!(subscription_status: "active")
    entity2.update!(subscription_status: "trial")

    active_entities = Entity.where(subscription_status: "active")
    assert_includes active_entities, entity1
    assert_not_includes active_entities, entity2
  end

  test "can calculate token usage percentage" do
    entity = entities(:one)
    entity.update!(token_usage: 25_000, token_limit: 100_000)

    usage_percent = (entity.token_usage.to_f / entity.token_limit * 100).round(2)
    assert_equal 25.0, usage_percent
  end
end
