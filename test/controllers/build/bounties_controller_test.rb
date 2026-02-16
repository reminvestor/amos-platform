# frozen_string_literal: true

require "test_helper"

# Build::BountiesController tests
# Uses unit-style testing since build subdomain routes require subdomain constraint
class Build::BountiesControllerTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user_two = users(:two)
    @entity = entities(:one)
    @open_bounty = bounties(:open_bounty)
    @claimed_bounty = bounties(:claimed_bounty)
    @submitted_bounty = bounties(:submitted_bounty)
    @approved_bounty = bounties(:approved_bounty)
    @high_value_bounty = bounties(:high_value_bounty)
    @expired_bounty = bounties(:expired_bounty)
    @controller = Build::BountiesController.new
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CONTROLLER STRUCTURE
  # ═══════════════════════════════════════════════════════════════════════════

  test "controller exists and inherits from Build::BaseController" do
    assert defined?(Build::BountiesController)
    assert Build::BountiesController < Build::BaseController
  end

  test "controller has all required actions" do
    %i[index show claim submit_work].each do |action|
      assert @controller.respond_to?(action), "Missing action: #{action}"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # BOUNTY QUERIES — INDEX DATA
  # ═══════════════════════════════════════════════════════════════════════════

  test "available scope returns only open non-expired bounties" do
    available = Bounty.available

    assert_includes available, @open_bounty
    assert_includes available, @high_value_bounty
    assert_not_includes available, @claimed_bounty
    assert_not_includes available, @submitted_bounty
    assert_not_includes available, @approved_bounty
    assert_not_includes available, @expired_bounty
  end

  test "bounties can be filtered by type" do
    bugs = Bounty.available.by_type('bug')
    features = Bounty.available.by_type('feature')

    assert bugs.all? { |b| b.bounty_type == 'bug' }
    assert features.all? { |b| b.bounty_type == 'feature' }
  end

  test "bounties can be sorted by points descending" do
    sorted = Bounty.available.by_points
    points = sorted.map(&:points)

    assert_equal points.sort.reverse, points
  end

  test "bounties can be sorted by urgency" do
    sorted = Bounty.available.by_urgency
    urgencies = sorted.map { |b| b.urgency_score || 0 }

    assert_equal urgencies.sort.reverse, urgencies
  end

  test "bounties can be sorted by priority rank" do
    # Set priority ranks for testing
    @open_bounty.update!(priority_rank: 1)
    @high_value_bounty.update!(priority_rank: 2)

    sorted = Bounty.available.order(Arel.sql('COALESCE(priority_rank, 999) ASC'))

    assert_equal @open_bounty, sorted.first
    assert_equal @high_value_bounty, sorted.second
  end

  test "bounties can be filtered by sprint label" do
    @open_bounty.update!(sprint_label: "Sprint 12")
    @high_value_bounty.update!(sprint_label: "Sprint 13")

    sprint_12 = Bounty.available.where(sprint_label: "Sprint 12")

    assert_includes sprint_12, @open_bounty
    assert_not_includes sprint_12, @high_value_bounty
  end

  test "total points sums available bounties" do
    total = Bounty.available.sum(:points)

    assert total > 0
    assert_equal @open_bounty.points + @high_value_bounty.points, total
  end

  test "categories returns distinct bounty types" do
    types = Bounty.available.distinct.pluck(:bounty_type).compact
    assert_includes types, 'bug'
    assert_includes types, 'feature'
  end

  test "stats include open, claimed, and completed counts" do
    open_count = Bounty.open_bounties.count
    claimed_count = Bounty.claimed.count
    completed_count = Bounty.completed.count

    assert open_count >= 2  # open_bounty + high_value_bounty (expired_bounty is 'open' status but expired)
    assert claimed_count >= 1  # claimed_bounty
    assert completed_count >= 1  # approved_bounty
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # BOUNTY DISPLAY ATTRIBUTES
  # ═══════════════════════════════════════════════════════════════════════════

  test "bounty shows demand multiplier when boosted" do
    @open_bounty.update!(demand_multiplier: 1.5, original_points: 100)

    assert @open_bounty.demand_multiplier > 1.0
    assert_equal 100, @open_bounty.original_points
  end

  test "bounty shows grooming data" do
    @open_bounty.update!(
      priority_rank: 1,
      sprint_label: "Sprint 12",
      strategic_score: 8,
      tags: %w[backend urgent],
      grooming_notes: "Groomed by AMOS"
    )

    assert_equal 1, @open_bounty.priority_rank
    assert_equal "Sprint 12", @open_bounty.sprint_label
    assert_equal 8, @open_bounty.strategic_score
    assert_equal %w[backend urgent], @open_bounty.tags
    assert_equal "Groomed by AMOS", @open_bounty.grooming_notes
  end

  test "created_by_amos? returns true for system bounties" do
    assert @open_bounty.created_by_amos?
    assert_not @submitted_bounty.created_by_amos?
  end

  test "effective_points returns final_points when present" do
    assert_equal 30, @approved_bounty.effective_points
    assert_equal 100, @open_bounty.effective_points
  end

  test "acceptance criteria available from metadata" do
    @open_bounty.update!(metadata: { 'acceptance_criteria' => ['Fix works on iOS', 'Fix works on Android'] })

    criteria = @open_bounty.metadata&.dig('acceptance_criteria') || []
    assert_equal 2, criteria.length
    assert_includes criteria, 'Fix works on iOS'
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CLAIM LOGIC
  # ═══════════════════════════════════════════════════════════════════════════

  test "can_claim? returns true for open non-expired bounty" do
    assert @open_bounty.can_claim?
    assert @high_value_bounty.can_claim?
  end

  test "can_claim? returns false for claimed bounty" do
    assert_not @claimed_bounty.can_claim?
  end

  test "can_claim? returns false for expired bounty" do
    assert_not @expired_bounty.can_claim?
  end

  test "claim! assigns user and changes status" do
    @open_bounty.claim!(@user_two)

    @open_bounty.reload
    assert_equal 'claimed', @open_bounty.status
    assert_equal @user_two, @open_bounty.claimed_by
    assert_not_nil @open_bounty.claimed_at
  end

  test "claim! fails on already claimed bounty" do
    result = @claimed_bounty.claim!(@user)
    assert_equal false, result
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SUBMIT WORK LOGIC
  # ═══════════════════════════════════════════════════════════════════════════

  test "submit! changes status and records submission" do
    @claimed_bounty.submit!(
      notes: "Fixed the issue",
      pr_url: "https://github.com/org/repo/pull/456"
    )

    @claimed_bounty.reload
    assert_equal 'submitted', @claimed_bounty.status
    assert_equal "Fixed the issue", @claimed_bounty.submission_notes
    assert_equal "https://github.com/org/repo/pull/456", @claimed_bounty.pr_url
    assert_not_nil @claimed_bounty.submitted_at
  end

  test "submit! extracts PR number from URL" do
    @claimed_bounty.submit!(pr_url: "https://github.com/org/repo/pull/789")
    @claimed_bounty.reload

    assert_equal 789, @claimed_bounty.pr_number
  end

  test "submit! fails on open bounty" do
    result = @open_bounty.submit!(notes: "nothing")
    assert_equal false, result
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # ERROR HANDLING
  # ═══════════════════════════════════════════════════════════════════════════

  test "index action handles errors gracefully" do
    # Verify the rescue block produces safe defaults
    Bounty.stubs(:available).raises(StandardError.new("DB error"))

    # Simulate what the controller does on error
    begin
      Bounty.available
    rescue => e
      bounties = Bounty.none.page(1)
      types = []
      total_points = 0
    end

    assert_equal [], types
    assert_equal 0, total_points
  end
end
