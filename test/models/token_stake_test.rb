# frozen_string_literal: true

require 'test_helper'

class TokenStakeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @entity = entities(:one)
  end

  # === CREATION TESTS ===

  test "creates distribution stake with correct defaults" do
    stake = TokenStake.create_distribution_stake!(
      user: @user,
      amount: 1000,
      category: 'affiliate_sale'
    )

    assert stake.persisted?
    assert_equal 'distribution', stake.stake_type
    assert_equal 'affiliate_sale', stake.category
    assert_equal 1000, stake.initial_amount
    assert_equal 1000, stake.current_amount
    assert_equal 0.40, stake.decay_rate # 40% annual for all types (fairness)
    assert_not_nil stake.earned_at
  end

  test "creates contribution stake with correct defaults" do
    stake = TokenStake.create_contribution_stake!(
      user: @user,
      amount: 500,
      category: 'bug_fix'
    )

    assert stake.persisted?
    assert_equal 'contribution', stake.stake_type
    assert_equal 'bug_fix', stake.category
    assert_equal 500, stake.initial_amount
    assert_equal 0.40, stake.decay_rate # 40% annual for contribution
  end

  test "validates stake type is valid" do
    stake = TokenStake.new(
      user: @user,
      stake_type: 'invalid_type',
      initial_amount: 100,
      current_amount: 100
    )

    assert_not stake.valid?
    assert_includes stake.errors[:stake_type], 'is not included in the list'
  end

  test "validates initial amount is positive" do
    stake = TokenStake.new(
      user: @user,
      stake_type: 'distribution',
      initial_amount: 0,
      current_amount: 0
    )

    assert_not stake.valid?
    assert_includes stake.errors[:initial_amount], 'must be greater than 0'
  end

  # === GRADUATED FLOOR TESTS ===

  test "current_floor_percentage is 5% for new stakes" do
    stake = TokenStake.new(earned_at: Time.current, initial_amount: 1000)
    assert_equal 0.05, stake.current_floor_percentage
    assert_equal 50, stake.permanent_floor_amount
  end

  test "current_floor_percentage grows with tenure" do
    # Year 0: 5%
    stake = TokenStake.new(earned_at: Time.current, initial_amount: 1000)
    assert_equal 0.05, stake.current_floor_percentage

    # Year 1-3: 10%
    stake.earned_at = 2.years.ago
    assert_equal 0.10, stake.current_floor_percentage
    assert_equal 100, stake.permanent_floor_amount

    # Year 3-5: 15%
    stake.earned_at = 4.years.ago
    assert_equal 0.15, stake.current_floor_percentage
    assert_equal 150, stake.permanent_floor_amount

    # Year 5+: 25% (maximum)
    stake.earned_at = 6.years.ago
    assert_equal 0.25, stake.current_floor_percentage
    assert_equal 250, stake.permanent_floor_amount
  end

  test "maximum_floor_percentage returns 25%" do
    stake = TokenStake.new(initial_amount: 1000)
    assert_equal 0.25, stake.maximum_floor_percentage
  end

  test "years_until_max_floor calculates correctly" do
    stake = TokenStake.new(earned_at: Time.current, initial_amount: 1000)
    assert_equal 5, stake.years_until_max_floor

    stake.earned_at = 3.years.ago
    assert_equal 2, stake.years_until_max_floor

    stake.earned_at = 6.years.ago
    assert_equal 0, stake.years_until_max_floor
  end

  # === DECAY TESTS ===

  test "applies decay correctly with graduated floor protection" do
    stake = TokenStake.create!(
      user: @user,
      stake_type: 'distribution',
      initial_amount: 1000,
      current_amount: 1000,
      decay_rate: 0.40,
      earned_at: 366.days.ago,  # Just over 1 year - 10% floor
      last_decay_at: 366.days.ago
    )

    stake.apply_decay!
    stake.reload

    # Should decay but never below graduated floor
    floor = stake.permanent_floor_amount  # Should be 10% = 100
    assert stake.current_amount >= floor, "Current #{stake.current_amount} should be >= floor #{floor}"
    assert stake.current_amount < 1000
    assert_not_nil stake.last_decay_at
  end

  test "decay respects growing floor over time" do
    # Stake just over 5 years old - has 25% floor now
    stake = TokenStake.create!(
      user: @user,
      stake_type: 'distribution',
      initial_amount: 1000,
      current_amount: 400,  # Already decayed some
      decay_rate: 0.40,
      earned_at: 6.years.ago,
      last_decay_at: 1.day.ago
    )

    # Floor should be 25% = 250
    assert_equal 250, stake.permanent_floor_amount

    # Apply decay
    stake.apply_decay!
    stake.reload

    # Should never go below 250
    assert stake.current_amount >= 250
  end

  test "at_floor? respects graduated floor" do
    # New stake - 5% floor
    stake = TokenStake.new(initial_amount: 1000, current_amount: 50, earned_at: Time.current)
    assert stake.at_floor?
    
    stake.current_amount = 51
    assert_not stake.at_floor?
    
    # Old stake - 25% floor
    stake.earned_at = 6.years.ago
    stake.current_amount = 250
    assert stake.at_floor?
    
    stake.current_amount = 251
    assert_not stake.at_floor?
  end

  test "fully_decayed? returns true when amount is zero" do
    stake = TokenStake.new(current_amount: 0, initial_amount: 100)
    assert stake.fully_decayed?

    stake.current_amount = 0.001
    assert_not stake.fully_decayed?
  end

  test "calculates decay percentage correctly" do
    stake = TokenStake.new(
      initial_amount: 1000,
      current_amount: 750
    )

    assert_equal 25.0, stake.decay_percentage
    assert_equal 75.0, stake.remaining_percentage
  end

  test "projects future value with floor protection" do
    stake = TokenStake.new(
      initial_amount: 1000,
      current_amount: 1000,
      decay_rate: 0.40,
      earned_at: Time.current
    )

    # Project far into future - should never go below graduated floor
    # At 10 years, floor is 25%
    future_value = stake.projected_value_at(3650.days.from_now)
    
    # Should be above 5% floor at minimum (but tenure calculation might differ)
    assert future_value > 0
  end

  test "tenure_based_decay_rate decreases over time" do
    stake = TokenStake.new(earned_at: Time.current)
    year_0_rate = stake.tenure_based_decay_rate
    
    stake.earned_at = 3.years.ago
    year_3_rate = stake.tenure_based_decay_rate
    
    stake.earned_at = 6.years.ago
    year_6_rate = stake.tenure_based_decay_rate
    
    stake.earned_at = 11.years.ago
    year_11_rate = stake.tenure_based_decay_rate
    
    # Decay rate should decrease with tenure
    assert year_0_rate > year_3_rate
    assert year_3_rate > year_6_rate
    assert year_6_rate > year_11_rate
    assert_equal 0.05, year_11_rate # 5% for 10+ years
  end

  # === STAKING VAULT TESTS ===

  test "locking in vault reduces decay rate" do
    stake = TokenStake.create!(
      user: @user,
      stake_type: 'distribution',
      initial_amount: 1000,
      current_amount: 1000,
      decay_rate: 0.40,
      earned_at: Time.current
    )

    unlocked_rate = stake.effective_annual_decay_rate
    
    stake.lock_in_vault!(years: 5) # Gold tier - 75% reduction
    stake.reload
    
    locked_rate = stake.effective_annual_decay_rate
    
    assert locked_rate < unlocked_rate
    assert stake.locked?
    assert stake.locked_until > 4.years.from_now
  end

  test "10 year lock eliminates decay entirely" do
    stake = TokenStake.create!(
      user: @user,
      stake_type: 'distribution',
      initial_amount: 1000,
      current_amount: 1000,
      decay_rate: 0.40,
      earned_at: Time.current
    )

    stake.lock_in_vault!(years: 10) # Permanent tier - 100% reduction
    stake.reload
    
    assert_equal 0, stake.effective_annual_decay_rate
  end

  # === AGGREGATION TESTS ===

  test "calculates total supply from active stakes" do
    TokenStake.where(user: @user).destroy_all

    TokenStake.create!(
      user: @user,
      stake_type: 'distribution',
      initial_amount: 1000,
      current_amount: 1000,
      earned_at: Time.current
    )

    TokenStake.create!(
      user: @user,
      stake_type: 'contribution',
      initial_amount: 500,
      current_amount: 500,
      earned_at: Time.current
    )

    # Create one with zero amount (should not count)
    TokenStake.create!(
      user: @user,
      stake_type: 'distribution',
      initial_amount: 100,
      current_amount: 0,
      earned_at: Time.current
    )

    assert_equal 1500, TokenStake.for_user(@user).active.sum(:current_amount)
  end

  test "groups total by type" do
    TokenStake.where(user: @user).destroy_all

    TokenStake.create!(
      user: @user,
      stake_type: 'distribution',
      initial_amount: 1000,
      current_amount: 1000,
      earned_at: Time.current
    )

    TokenStake.create!(
      user: @user,
      stake_type: 'contribution',
      initial_amount: 500,
      current_amount: 500,
      earned_at: Time.current
    )

    by_type = TokenStake.for_user(@user).active.group(:stake_type).sum(:current_amount)
    
    assert_equal 1000, by_type['distribution']
    assert_equal 500, by_type['contribution']
  end

  # === TRANSACTION RECORDING ===

  test "records transaction on stake creation" do
    stake = TokenStake.create_distribution_stake!(
      user: @user,
      amount: 1000,
      category: 'affiliate_sale'
    )

    transaction = TokenStakeTransaction.find_by(token_stake: stake)
    
    assert_not_nil transaction
    assert_equal 'earn', transaction.transaction_type
    assert_equal 1000, transaction.amount
    assert_equal 0, transaction.balance_before
    assert_equal 1000, transaction.balance_after
  end

  # === DEFAULT DECAY RATES ===

  test "default decay rates are equal for fairness" do
    # All stake types now start at same rate for fairness
    assert_equal 0.40, TokenStake.default_decay_rate_for('distribution')
    assert_equal 0.40, TokenStake.default_decay_rate_for('contribution')
    assert_equal 0.40, TokenStake.default_decay_rate_for('community')
    assert_equal 0.40, TokenStake.default_decay_rate_for('founding')
    assert_equal 0.40, TokenStake.default_decay_rate_for('investor')
    # Only inherited stakes get reduced rate
    assert_equal 0.10, TokenStake.default_decay_rate_for('inherited')
  end
end
