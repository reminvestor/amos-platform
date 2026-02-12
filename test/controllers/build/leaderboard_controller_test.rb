# frozen_string_literal: true

require "test_helper"

# Build portal controller tests
# Note: Build subdomain routes require subdomain constraint which isn't
# available in standard integration tests. These tests verify the
# controller logic via direct unit testing instead.
class Build::LeaderboardControllerTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @entity = entities(:one)
    @controller = Build::LeaderboardController.new
  end

  # --- Controller structure ---

  test "controller class exists and inherits from Build::BaseController" do
    assert defined?(Build::LeaderboardController)
    assert Build::LeaderboardController < Build::BaseController
  end

  test "controller has index action" do
    assert @controller.respond_to?(:index)
  end

  # --- fetch_economy_stats ---

  test "fetch_economy_stats returns hash with expected keys" do
    TokenEconomyService.stubs(:economy_stats).returns({
      total_supply: 1_000_000,
      total_stakeholders: 42,
      ownership_concentration: { top_10_percent: 65.5 }
    })
    ContributionRewardCalculator.stubs(:current_daily_emission).returns(100)

    result = @controller.send(:fetch_economy_stats)

    assert_kind_of Hash, result
    assert_equal 1_000_000, result[:total_staked]
    assert_equal 42, result[:active_stakeholders]
    assert_equal 100, result[:daily_emission]
    assert_equal 65.5, result[:concentration]
  end

  test "fetch_economy_stats returns zero defaults on service error" do
    TokenEconomyService.stubs(:economy_stats).raises(StandardError.new("DB down"))

    result = @controller.send(:fetch_economy_stats)

    assert_equal 0, result[:total_staked]
    assert_equal 0, result[:active_stakeholders]
    assert_equal 0, result[:daily_emission]
    assert_equal 0, result[:concentration]
  end

  # --- fetch_top_stakeholders ---

  test "fetch_top_stakeholders returns empty array on error" do
    TokenStake.stubs(:top_stakeholders).raises(StandardError.new("table missing"))

    result = @controller.send(:fetch_top_stakeholders)

    assert_equal [], result
  end

  test "fetch_top_stakeholders returns ranked entries" do
    mock_row = Struct.new(:user_id, :first_name, :last_name, :total_stake, keyword_init: true)
    rows = [
      mock_row.new(user_id: 1, first_name: "Alice", last_name: "A", total_stake: 500.0),
      mock_row.new(user_id: 2, first_name: nil, last_name: nil, total_stake: 300.0)
    ]
    TokenStake.stubs(:top_stakeholders).returns(rows)
    TokenStake.stubs(:total_supply).returns(1000.0)

    result = @controller.send(:fetch_top_stakeholders)

    assert_equal 2, result.length
    assert_equal 1, result[0][:rank]
    assert_equal "Alice", result[0][:display_name]
    assert_equal 500.0, result[0][:total_stake]
    assert_equal 50.0, result[0][:ownership_percentage]
    assert_equal 2, result[1][:rank]
    assert_equal "User 2", result[1][:display_name]
  end

  # --- fetch_top_contributors ---

  test "fetch_top_contributors returns empty array on error" do
    Contribution.stubs(:leaderboard).raises(StandardError.new("table missing"))

    result = @controller.send(:fetch_top_contributors)

    assert_equal [], result
  end

  test "fetch_top_contributors returns ranked entries" do
    mock_row = Struct.new(:user_id, :first_name, :last_name, :contribution_count, :total_stake, keyword_init: true)
    rows = [
      mock_row.new(user_id: 1, first_name: "Bob", last_name: "B", contribution_count: 10, total_stake: 250.0)
    ]
    Contribution.stubs(:leaderboard).returns(rows)

    result = @controller.send(:fetch_top_contributors)

    assert_equal 1, result.length
    assert_equal 1, result[0][:rank]
    assert_equal "Bob", result[0][:display_name]
    assert_equal 10, result[0][:contribution_count]
    assert_equal 250.0, result[0][:total_stake]
  end
end
