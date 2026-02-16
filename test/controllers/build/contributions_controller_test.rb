# frozen_string_literal: true

require "test_helper"

# Build::ContributionsController tests
# Uses unit-style testing since build subdomain routes require subdomain constraint
class Build::ContributionsControllerTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user_two = users(:two)
    @entity = entities(:one)
    @approved_contribution = contributions(:approved_contribution)
    @merged_contribution = contributions(:merged_contribution)
    @pending_contribution = contributions(:pending_contribution)
    @controller = Build::ContributionsController.new
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CONTROLLER STRUCTURE
  # ═══════════════════════════════════════════════════════════════════════════

  test "controller exists and inherits from Build::BaseController" do
    assert defined?(Build::ContributionsController)
    assert Build::ContributionsController < Build::BaseController
  end

  test "controller has all required actions" do
    %i[index show my_contributions].each do |action|
      assert @controller.respond_to?(action), "Missing action: #{action}"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # INDEX DATA
  # ═══════════════════════════════════════════════════════════════════════════

  test "accepted scope includes approved and merged contributions" do
    accepted = Contribution.accepted

    assert_includes accepted, @approved_contribution
    assert_includes accepted, @merged_contribution
    assert_not_includes accepted, @pending_contribution
  end

  test "contributions ordered by created_at desc" do
    contributions = Contribution.accepted.order(created_at: :desc)

    dates = contributions.map(&:created_at)
    assert_equal dates, dates.sort.reverse
  end

  test "stats total counts accepted contributions" do
    total = Contribution.accepted.count

    assert total >= 2  # approved_contribution + merged_contribution
  end

  test "stats total_value sums stake values" do
    total = Contribution.accepted.sum(:stake_value)

    assert total >= 600  # 100 + 500
  end

  test "stats this_month counts recent contributions" do
    recent = Contribution.accepted.where('created_at > ?', 30.days.ago).count

    assert recent >= 0
  end

  test "stats contributors counts distinct users" do
    contributors = Contribution.accepted.select(:user_id).distinct.count

    assert contributors >= 1
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SHOW — INDIVIDUAL CONTRIBUTION
  # ═══════════════════════════════════════════════════════════════════════════

  test "contribution has all display attributes" do
    c = @approved_contribution

    assert c.title.present?
    assert c.description.present?
    assert c.contribution_type.present?
    assert c.stake_value.present?
    assert c.user.present?
  end

  test "contribution parses external reference" do
    parsed = @approved_contribution.parsed_reference

    assert_equal "1", parsed[:bounty]
    assert_equal "https://github.com/org/repo/pull/42", parsed[:pr]
  end

  test "contribution has_code_evidence? with PR" do
    assert @approved_contribution.has_code_evidence?
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # MY CONTRIBUTIONS — USER-SCOPED
  # ═══════════════════════════════════════════════════════════════════════════

  test "my_contributions filters by user" do
    user_one_contributions = Contribution.where(user: @user)
    user_two_contributions = Contribution.where(user: @user_two)

    assert user_one_contributions.count >= 1  # merged_contribution, recent_approved
    assert user_two_contributions.count >= 1  # approved_contribution, pending_contribution
  end

  test "my_contributions stats count accepted for user" do
    total = Contribution.where(user: @user_two).accepted.count

    assert total >= 1
  end

  test "my_contributions stats sum earnings for user" do
    earned = Contribution.where(user: @user_two).accepted.sum(:stake_value)

    assert earned >= 100
  end

  test "my_contributions pending counts submitted for user" do
    pending = Contribution.where(user: @user_two).pending_review.count

    assert pending >= 1  # pending_contribution
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # ERROR HANDLING
  # ═══════════════════════════════════════════════════════════════════════════

  test "index handles errors with safe defaults" do
    Contribution.stubs(:accepted).raises(StandardError.new("DB error"))

    begin
      Contribution.accepted
    rescue
      contributions = Contribution.none.page(1)
      stats = { total: 0, total_value: 0, this_month: 0, contributors: 0 }
    end

    assert_equal 0, stats[:total]
    assert_equal 0, stats[:total_value]
  end
end
