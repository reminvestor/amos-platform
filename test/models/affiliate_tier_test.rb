require "test_helper"

class AffiliateTierTest < ActiveSupport::TestCase
  # Validation tests
  test "should require name" do
    tier = AffiliateTier.new(
      commission_rate: 0.20,
      min_referrals: 0
    )
    tier.name = nil

    assert_not tier.valid?
    assert_includes tier.errors[:name], "can't be blank"
  end

  test "name should be unique" do
    existing = affiliate_tiers(:bronze)
    tier = AffiliateTier.new(
      name: existing.name,
      commission_rate: 0.25,
      min_referrals: 5
    )

    assert_not tier.valid?
    assert_includes tier.errors[:name], "has already been taken"
  end

  test "commission_rate should be between 0 and 1" do
    tier = affiliate_tiers(:bronze)

    tier.commission_rate = -0.1
    assert_not tier.valid?

    tier.commission_rate = 1.1
    assert_not tier.valid?

    tier.commission_rate = 0.5
    assert tier.valid?
  end

  test "commission_rate accepts 0 and 1 as valid values" do
    tier = affiliate_tiers(:bronze)

    tier.commission_rate = 0
    assert tier.valid?

    tier.commission_rate = 1
    assert tier.valid?
  end

  test "min_referrals should be greater than or equal to 0" do
    tier = affiliate_tiers(:bronze)

    tier.min_referrals = -1
    assert_not tier.valid?

    tier.min_referrals = 0
    assert tier.valid?

    tier.min_referrals = 10
    assert tier.valid?
  end

  # Scope tests
  test "active scope should return only active tiers" do
    active_tiers = AffiliateTier.active

    assert active_tiers.count > 0
    assert active_tiers.all?(&:is_active)
  end

  test "ordered scope should order by min_referrals ascending" do
    tiers = AffiliateTier.ordered.to_a

    if tiers.size >= 2
      (0...tiers.size - 1).each do |i|
        assert tiers[i].min_referrals <= tiers[i + 1].min_referrals
      end
    end
  end

  # Data storage tests
  test "should store benefits as json" do
    tier = affiliate_tiers(:bronze)

    assert_instance_of Hash, tier.benefits
    assert tier.benefits['perks'].is_a?(Array)
  end

  test "should allow empty benefits" do
    tier = AffiliateTier.create!(
      name: 'Test Tier',
      commission_rate: 0.15,
      min_referrals: 0
    )

    # Benefits should default to {} based on migration
    assert_equal({}, tier.benefits)
  end

  test "is_active should default to true" do
    tier = AffiliateTier.create!(
      name: 'New Tier',
      commission_rate: 0.22,
      min_referrals: 3
    )

    assert tier.is_active
  end

  # Business logic tests
  test "should support tier progression" do
    bronze = affiliate_tiers(:bronze)
    silver = affiliate_tiers(:silver)
    gold = affiliate_tiers(:gold)

    assert bronze.min_referrals < silver.min_referrals
    assert silver.min_referrals < gold.min_referrals

    assert bronze.commission_rate < silver.commission_rate
    assert silver.commission_rate < gold.commission_rate
  end

  test "should be able to deactivate a tier" do
    tier = affiliate_tiers(:bronze)

    assert tier.is_active

    tier.update!(is_active: false)

    assert_not tier.is_active
    assert_not AffiliateTier.active.include?(tier)
  end

  test "should support multiple benefit types" do
    tier = AffiliateTier.create!(
      name: 'Premium',
      commission_rate: 0.28,
      min_referrals: 15,
      benefits: {
        perks: ['Priority support', 'Dedicated manager'],
        features: ['Early access', 'Custom materials'],
        bonuses: { signup: 100, milestone: 500 }
      }
    )

    assert_equal ['Priority support', 'Dedicated manager'], tier.benefits['perks']
    assert_equal 100, tier.benefits['bonuses']['signup']
  end
end
