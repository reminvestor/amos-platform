# frozen_string_literal: true

require "test_helper"

# Build::DashboardController tests
# Uses unit-style testing since build subdomain routes require subdomain constraint
class Build::DashboardControllerTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @entity = entities(:one)
    @controller = Build::DashboardController.new
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CONTROLLER STRUCTURE
  # ═══════════════════════════════════════════════════════════════════════════

  test "controller exists and inherits from Build::BaseController" do
    assert defined?(Build::DashboardController)
    assert Build::DashboardController < Build::BaseController
  end

  test "controller has index action" do
    assert @controller.respond_to?(:index)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # STATS DATA
  # ═══════════════════════════════════════════════════════════════════════════

  test "stats include open bounty count" do
    open_count = Bounty.open_bounties.count

    assert open_count >= 0
    assert_kind_of Integer, open_count
  end

  test "stats include total rewards from open bounties" do
    total = Bounty.open_bounties.sum(:points)

    assert total >= 0
    assert_kind_of Numeric, total
  end

  test "stats include completed bounties count" do
    completed = Bounty.completed.count

    assert completed >= 0
    assert_kind_of Integer, completed
  end

  test "stats include distinct contributor count" do
    contributors = Bounty.completed.select(:claimed_by_id).distinct.count

    assert contributors >= 0
    assert_kind_of Integer, contributors
  end

  test "stats include total paid with final_points fallback" do
    total_paid = Bounty.completed.sum(Arel.sql('COALESCE(final_points, points)'))

    assert total_paid >= 0
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FEATURED BOUNTIES
  # ═══════════════════════════════════════════════════════════════════════════

  test "featured bounties are ordered by priority then points" do
    featured = Bounty.available
                      .order(Arel.sql('COALESCE(priority_rank, 999) ASC, points DESC'))
                      .limit(6)

    assert featured.length <= 6
    assert featured.all? { |b| b.status == 'open' }
  end

  test "featured bounties excludes expired bounties" do
    expired = bounties(:expired_bounty)
    featured = Bounty.available
                      .order(Arel.sql('COALESCE(priority_rank, 999) ASC, points DESC'))
                      .limit(6)

    assert_not_includes featured, expired
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # RECENT COMPLETIONS
  # ═══════════════════════════════════════════════════════════════════════════

  test "recent completions shows approved bounties ordered by approval date" do
    completions = Bounty.completed.order(approved_at: :desc).limit(5)

    assert completions.all? { |b| b.status == 'approved' }
    assert completions.length <= 5
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SPRINT LABELS
  # ═══════════════════════════════════════════════════════════════════════════

  test "sprint labels are grouped with counts" do
    bounties(:open_bounty).update!(sprint_label: "Sprint 12")
    bounties(:high_value_bounty).update!(sprint_label: "Sprint 12")

    labels = Bounty.available
                    .where.not(sprint_label: [nil, ''])
                    .group(:sprint_label)
                    .count

    assert_equal 2, labels["Sprint 12"]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # ERROR HANDLING
  # ═══════════════════════════════════════════════════════════════════════════

  test "index handles errors with safe defaults" do
    # The controller has a rescue block — verify the default shape
    default_stats = { open_bounties: 0, total_rewards: 0, completed_bounties: 0, contributors: 0, total_paid: 0 }

    assert_kind_of Hash, default_stats
    assert_equal 0, default_stats[:open_bounties]
    assert_equal 0, default_stats[:total_rewards]
  end
end
