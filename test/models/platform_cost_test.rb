# frozen_string_literal: true

require "test_helper"

class PlatformCostTest < ActiveSupport::TestCase
  # === VALIDATIONS ===

  test "valid platform cost" do
    cost = PlatformCost.new(
      category: 'compute',
      amount: 5000.00,
      recorded_at: Time.current,
      description: 'AWS monthly bill'
    )
    assert cost.valid?
  end

  test "requires category" do
    cost = PlatformCost.new(
      amount: 5000.00,
      recorded_at: Time.current
    )
    assert_not cost.valid?
    assert cost.errors[:category].present?
  end

  test "requires valid category" do
    cost = PlatformCost.new(
      category: 'invalid_category',
      amount: 5000.00,
      recorded_at: Time.current
    )
    assert_not cost.valid?
    assert cost.errors[:category].present?
  end

  test "accepts all valid categories" do
    PlatformCost::CATEGORIES.each do |category|
      cost = PlatformCost.new(
        category: category,
        amount: 1000.00,
        recorded_at: Time.current
      )
      assert cost.valid?, "Category '#{category}' should be valid"
    end
  end

  test "requires positive amount" do
    cost = PlatformCost.new(
      category: 'compute',
      amount: 0,
      recorded_at: Time.current
    )
    assert_not cost.valid?
    assert cost.errors[:amount].present?
  end

  test "requires recorded_at" do
    cost = PlatformCost.new(
      category: 'compute',
      amount: 5000.00
    )
    assert_not cost.valid?
    assert cost.errors[:recorded_at].present?
  end

  # === SCOPES ===

  test "in_period scope filters by date range" do
    # Create costs at different times
    old_cost = PlatformCost.create!(
      category: 'compute',
      amount: 1000,
      recorded_at: 60.days.ago
    )
    
    recent_cost = PlatformCost.create!(
      category: 'compute',
      amount: 2000,
      recorded_at: 5.days.ago
    )

    results = PlatformCost.in_period(30.days.ago, Time.current)
    
    assert_includes results, recent_cost
    assert_not_includes results, old_cost
  end

  test "by_category scope filters by category" do
    compute_cost = PlatformCost.create!(
      category: 'compute',
      amount: 1000,
      recorded_at: Time.current
    )
    
    infra_cost = PlatformCost.create!(
      category: 'infrastructure',
      amount: 2000,
      recorded_at: Time.current
    )

    results = PlatformCost.by_category('compute')
    
    assert_includes results, compute_cost
    assert_not_includes results, infra_cost
  end

  test "monthly scope filters monthly costs" do
    monthly_cost = PlatformCost.create!(
      category: 'compute',
      amount: 1000,
      recorded_at: Time.current,
      period_type: 'monthly'
    )
    
    one_time_cost = PlatformCost.create!(
      category: 'compute',
      amount: 500,
      recorded_at: Time.current,
      period_type: 'one_time'
    )

    results = PlatformCost.monthly
    
    assert_includes results, monthly_cost
    assert_not_includes results, one_time_cost
  end

  # === CLASS METHODS ===

  test "total_for_period sums costs in range" do
    # Clear existing costs
    PlatformCost.delete_all
    
    PlatformCost.create!(
      category: 'compute',
      amount: 1000,
      recorded_at: 5.days.ago
    )
    
    PlatformCost.create!(
      category: 'infrastructure',
      amount: 500,
      recorded_at: 3.days.ago
    )
    
    # Old cost outside range
    PlatformCost.create!(
      category: 'compute',
      amount: 2000,
      recorded_at: 60.days.ago
    )

    total = PlatformCost.total_for_period(30.days.ago)
    
    assert_equal 1500, total
  end

  test "breakdown_by_category groups and sums" do
    PlatformCost.delete_all
    
    PlatformCost.create!(category: 'compute', amount: 1000, recorded_at: Time.current)
    PlatformCost.create!(category: 'compute', amount: 500, recorded_at: Time.current)
    PlatformCost.create!(category: 'infrastructure', amount: 200, recorded_at: Time.current)

    breakdown = PlatformCost.breakdown_by_category(30.days.ago)
    
    assert_equal 1500, breakdown['compute']
    assert_equal 200, breakdown['infrastructure']
  end

  # === ASSOCIATIONS ===

  test "belongs to recorded_by user" do
    user = users(:one)
    
    cost = PlatformCost.create!(
      category: 'compute',
      amount: 1000,
      recorded_at: Time.current,
      recorded_by: user
    )
    
    assert_equal user, cost.recorded_by
  end

  test "recorded_by is optional" do
    cost = PlatformCost.new(
      category: 'compute',
      amount: 1000,
      recorded_at: Time.current,
      recorded_by: nil
    )
    
    assert cost.valid?
  end

  # === METADATA ===

  test "stores metadata as JSON" do
    cost = PlatformCost.create!(
      category: 'third_party',
      amount: 99,
      recorded_at: Time.current,
      metadata: { vendor: 'Stripe', invoice_id: 'INV-123' }
    )

    cost.reload
    assert_equal 'Stripe', cost.metadata['vendor']
    assert_equal 'INV-123', cost.metadata['invoice_id']
  end
end
