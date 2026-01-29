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
    assert_equal 0.50, stake.decay_rate # 50% annual for distribution
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

  # === DECAY TESTS ===

  test "applies decay correctly" do
    stake = TokenStake.create!(
      user: @user,
      stake_type: 'distribution',
      initial_amount: 1000,
      current_amount: 1000,
      decay_rate: 0.50, # 50% annual
      earned_at: 366.days.ago,
      last_decay_at: 366.days.ago
    )

    stake.apply_decay!
    stake.reload

    # After 1 year with 50% annual decay, should be ~500
    assert stake.current_amount < 1000
    assert stake.current_amount > 400 # Some tolerance for calculation
    assert stake.current_amount < 600
    assert_not_nil stake.last_decay_at
    assert stake.total_decayed > 0
  end

  test "decay does not go below zero" do
    stake = TokenStake.create!(
      user: @user,
      stake_type: 'distribution',
      initial_amount: 100,
      current_amount: 100,
      decay_rate: 0.99, # 99% annual decay
      earned_at: 1000.days.ago,
      last_decay_at: 1000.days.ago
    )

    stake.apply_decay!
    stake.reload

    assert stake.current_amount >= 0
  end

  test "fully_decayed? returns true when amount is zero" do
    stake = TokenStake.new(current_amount: 0)
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

  test "projects future value correctly" do
    stake = TokenStake.new(
      current_amount: 1000,
      decay_rate: 0.50 # 50% annual
    )

    # After 365 days, should be ~500
    future_value = stake.projected_value_at(365.days.from_now)
    assert future_value < 600
    assert future_value > 400
  end

  test "calculates half life in days" do
    stake = TokenStake.new(decay_rate: 0.50) # 50% annual decay
    
    # With 50% annual decay, half-life should be ~1 year
    half_life = stake.half_life_days
    assert half_life > 300
    assert half_life < 400
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

  test "default decay rates for each stake type" do
    assert_equal 0.50, TokenStake.default_decay_rate_for('distribution')
    assert_equal 0.40, TokenStake.default_decay_rate_for('contribution')
    assert_equal 0.30, TokenStake.default_decay_rate_for('community')
    assert_equal 0.10, TokenStake.default_decay_rate_for('founding')
    assert_equal 0.05, TokenStake.default_decay_rate_for('investor')
  end
end
