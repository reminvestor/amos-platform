# frozen_string_literal: true

require 'test_helper'

class TokenEconomyServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user2 = users(:two)
    @entity = entities(:one)
    
    # Clean up existing stakes for predictable tests
    TokenStake.destroy_all
    TokenStakeTransaction.destroy_all
  end

  # === DISTRIBUTION STAKES ===

  test "awards affiliate stake for approved commission" do
    affiliate = Affiliate.create!(
      user: @user,
      affiliate_code: 'TEST123',
      status: :active,
      commission_rate: 0.20
    )

    referral = Referral.create!(
      affiliate: affiliate,
      referral_code_used: 'TEST123',
      status: :converted
    )

    commission = Commission.create!(
      affiliate: affiliate,
      referral: referral,
      entity: @entity,
      commission_type: 'first_payment',
      amount: 100.00,
      status: :approved,
      earned_at: Time.current
    )

    stake = TokenEconomyService.award_affiliate_stake!(commission)

    assert_not_nil stake
    assert_equal @user, stake.user
    assert_equal 'distribution', stake.stake_type
    assert_equal 'affiliate_sale', stake.category
    # 100 * 100 (multiplier) * halving_multiplier = base tokens
    # Halving may reduce this depending on platform age
    base_amount = 100 * 100
    expected = TokenStake.calculate_stake_with_halving(base_amount)
    assert_equal expected, stake.initial_amount
  end

  test "does not award stake for pending commission" do
    affiliate = Affiliate.create!(
      user: @user,
      affiliate_code: 'TEST456',
      status: :active,
      commission_rate: 0.20
    )

    referral = Referral.create!(
      affiliate: affiliate,
      referral_code_used: 'TEST456',
      status: :pending
    )

    commission = Commission.create!(
      affiliate: affiliate,
      referral: referral,
      entity: @entity,
      commission_type: 'first_payment',
      amount: 100.00,
      status: :pending,
      earned_at: Time.current
    )

    stake = TokenEconomyService.award_affiliate_stake!(commission)

    assert_nil stake
  end

  test "awards referral stake for converted referral" do
    affiliate = Affiliate.create!(
      user: @user,
      affiliate_code: 'REF123',
      status: :active,
      commission_rate: 0.20
    )

    referral = Referral.create!(
      affiliate: affiliate,
      referral_code_used: 'REF123',
      referred_entity: @entity,
      status: :converted,
      converted_at: Time.current
    )

    stake = TokenEconomyService.award_referral_stake!(referral)

    assert_not_nil stake
    assert_equal 'distribution', stake.stake_type
    assert_equal 'referral_conversion', stake.category
    assert_equal 50, stake.initial_amount # Default multiplier
  end

  # === CONTRIBUTION STAKES ===

  test "awards contribution stake for approved contribution" do
    contribution = Contribution.create!(
      user: @user,
      contribution_type: 'feature',
      title: 'New feature',
      description: 'Feature description',
      status: :approved,
      stake_value: 1500
    )

    stake = TokenEconomyService.award_contribution_stake!(contribution)

    assert_not_nil stake
    assert_equal 'contribution', stake.stake_type
    assert_equal 'feature', stake.category
    assert_equal 1500, stake.initial_amount
  end

  # === DECAY MANAGEMENT ===

  test "applies daily decay to all active stakes" do
    # Create stakes with old dates
    stake1 = TokenStake.create!(
      user: @user,
      stake_type: 'distribution',
      initial_amount: 1000,
      current_amount: 1000,
      decay_rate: 0.50,
      earned_at: 400.days.ago,
      last_decay_at: 400.days.ago
    )

    stake2 = TokenStake.create!(
      user: @user2,
      stake_type: 'contribution',
      initial_amount: 500,
      current_amount: 500,
      decay_rate: 0.40,
      earned_at: 400.days.ago,
      last_decay_at: 400.days.ago
    )

    result = TokenEconomyService.apply_daily_decay!

    assert_equal 2, result[:stakes_processed]
    assert result[:total_decayed] > 0

    stake1.reload
    stake2.reload

    assert stake1.current_amount < 1000
    assert stake2.current_amount < 500
  end

  # === REVENUE DISTRIBUTION ===

  test "calculates revenue distribution proportionally" do
    TokenStake.create!(
      user: @user,
      stake_type: 'distribution',
      initial_amount: 600,
      current_amount: 600,
      earned_at: Time.current
    )

    TokenStake.create!(
      user: @user2,
      stake_type: 'distribution',
      initial_amount: 400,
      current_amount: 400,
      earned_at: Time.current
    )

    # Total: 1000, user1 has 60%, user2 has 40%
    # Revenue: $10,000, token holder pool: $5,000 (50%)
    distribution = TokenEconomyService.calculate_revenue_distribution(10_000)

    assert_equal 3000.0, distribution[@user.id] # 60% of $5,000
    assert_equal 2000.0, distribution[@user2.id] # 40% of $5,000
  end

  test "returns empty distribution when no stakes exist" do
    distribution = TokenEconomyService.calculate_revenue_distribution(10_000)
    assert_equal({}, distribution)
  end

  # === TRANSPARENCY METRICS ===

  test "economy_stats returns comprehensive data" do
    TokenStake.create!(
      user: @user,
      stake_type: 'distribution',
      initial_amount: 1000,
      current_amount: 1000,
      earned_at: Time.current
    )

    TokenStake.create!(
      user: @user2,
      stake_type: 'contribution',
      initial_amount: 500,
      current_amount: 500,
      earned_at: Time.current
    )

    stats = TokenEconomyService.economy_stats

    assert_equal 1500, stats[:total_supply]
    assert_equal 2, stats[:active_stakes]
    assert_equal 2, stats[:total_stakeholders]
    assert stats[:supply_by_type].key?('distribution')
    assert stats[:supply_by_type].key?('contribution')
    assert_respond_to stats[:top_stakeholders], :each
    assert stats[:ownership_concentration].key?(:gini)
    assert stats[:decay_stats].key?(:total_decayed_all_time)
  end

  test "user_profile returns user-specific data" do
    TokenStake.create!(
      user: @user,
      stake_type: 'distribution',
      initial_amount: 1000,
      current_amount: 800,
      total_decayed: 200,
      earned_at: 30.days.ago
    )

    profile = TokenEconomyService.user_profile(@user)

    assert_equal 800, profile[:total_stake]
    assert profile[:ownership_percentage] > 0
    assert profile[:stakes_by_type].key?('distribution')
    assert_equal 1, profile[:stake_count]
    assert_equal 1000, profile[:total_earned]
    assert_equal 200, profile[:total_decayed]
  end

  test "public_ownership_distribution returns formatted data" do
    TokenStake.create!(
      user: @user,
      stake_type: 'distribution',
      initial_amount: 600,
      current_amount: 600,
      earned_at: Time.current
    )

    TokenStake.create!(
      user: @user2,
      stake_type: 'distribution',
      initial_amount: 400,
      current_amount: 400,
      earned_at: Time.current
    )

    distribution = TokenEconomyService.public_ownership_distribution

    assert_equal 2, distribution.length
    
    # Should be sorted by stake descending
    first = distribution.first
    assert first[:total_stake] >= distribution.last[:total_stake]
    
    # Should have required fields
    assert first.key?(:user_id)
    assert first.key?(:display_name)
    assert first.key?(:total_stake)
    assert first.key?(:ownership_percentage)
    
    # Percentages should sum to 100
    total_percentage = distribution.sum { |d| d[:ownership_percentage] }
    assert_in_delta 100.0, total_percentage, 0.01
  end

  # === INTEGRATION HOOKS ===

  test "on_commission_approved creates stake" do
    affiliate = Affiliate.create!(
      user: @user,
      affiliate_code: 'HOOK123',
      status: :active,
      commission_rate: 0.20
    )

    referral = Referral.create!(
      affiliate: affiliate,
      referral_code_used: 'HOOK123',
      status: :converted
    )

    commission = Commission.create!(
      affiliate: affiliate,
      referral: referral,
      entity: @entity,
      commission_type: 'first_payment',
      amount: 50.00,
      status: :approved,
      earned_at: Time.current
    )

    stake = TokenEconomyService.on_commission_approved(commission)

    assert_not_nil stake
    assert_equal commission, stake.source
  end

  test "on_commission_approved handles errors gracefully" do
    # Pass invalid commission
    result = TokenEconomyService.on_commission_approved(nil)
    assert_nil result
  end

  # === REVENUE ALLOCATION CONSTANTS ===

  test "revenue allocation percentages sum to 100%" do
    total = TokenEconomyService::REVENUE_ALLOCATION.values.sum
    assert_equal 1.0, total
  end

  test "multipliers are positive" do
    TokenEconomyService::DISTRIBUTION_MULTIPLIERS.each do |category, multiplier|
      assert multiplier > 0, "#{category} multiplier should be positive"
    end

    TokenEconomyService::CONTRIBUTION_MULTIPLIERS.each do |category, multiplier|
      assert multiplier > 0, "#{category} multiplier should be positive"
    end
  end
end
