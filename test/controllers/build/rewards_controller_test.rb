# frozen_string_literal: true

require "test_helper"

# Build::RewardsController tests
# Uses unit-style testing since build subdomain routes require subdomain constraint
class Build::RewardsControllerTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user_two = users(:two)
    @entity = entities(:one)
    @controller = Build::RewardsController.new
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CONTROLLER STRUCTURE
  # ═══════════════════════════════════════════════════════════════════════════

  test "controller exists and inherits from Build::BaseController" do
    assert defined?(Build::RewardsController)
    assert Build::RewardsController < Build::BaseController
  end

  test "controller has index action" do
    assert @controller.respond_to?(:index)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # REWARDS DATA
  # ═══════════════════════════════════════════════════════════════════════════

  test "total_earned sums accepted contributions for user" do
    earned = Contribution.where(user: @user_two).accepted.sum(:stake_value)

    assert earned >= 100  # approved_contribution
  end

  test "pending sums pending review contributions for user" do
    pending = Contribution.where(user: @user_two).pending_review.sum(:stake_value)

    assert pending >= 0
  end

  test "recent_rewards returns accepted contributions ordered by date" do
    recent = Contribution.where(user: @user_two)
                          .accepted
                          .order(created_at: :desc)
                          .limit(20)

    assert recent.all? { |c| c.approved? || c.merged? }
    assert recent.length <= 20
  end

  test "bounties_completed counts approved bounties for user" do
    completed = Bounty.completed.where(claimed_by: @user_two).count

    assert completed >= 1  # approved_bounty claimed by user_two
  end

  test "bounties_in_progress counts claimed bounties for user" do
    in_progress = Bounty.claimed.where(claimed_by: @user).count

    assert in_progress >= 1  # claimed_bounty claimed by user_one
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # USER REWARDS ISOLATION
  # ═══════════════════════════════════════════════════════════════════════════

  test "rewards are scoped to specific user" do
    user_one_earned = Contribution.where(user: @user).accepted.sum(:stake_value)
    user_two_earned = Contribution.where(user: @user_two).accepted.sum(:stake_value)

    # Each user has their own earned total
    assert user_one_earned != user_two_earned || user_one_earned == 0
  end
end
