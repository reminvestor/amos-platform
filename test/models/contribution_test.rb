# frozen_string_literal: true

require 'test_helper'

class ContributionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "creates contribution with valid attributes" do
    contribution = Contribution.new(
      user: @user,
      contribution_type: 'feature',
      title: 'Add new dashboard widget',
      description: 'Implemented a new KPI widget for the dashboard'
    )

    assert contribution.valid?
    assert contribution.save
    assert_equal 'submitted', contribution.status
  end

  test "validates contribution type is valid" do
    contribution = Contribution.new(
      user: @user,
      contribution_type: 'invalid',
      title: 'Test',
      description: 'Test'
    )

    assert_not contribution.valid?
    assert_includes contribution.errors[:contribution_type], 'is not included in the list'
  end

  test "validates title presence" do
    contribution = Contribution.new(
      user: @user,
      contribution_type: 'feature',
      description: 'Test'
    )

    assert_not contribution.valid?
    assert_includes contribution.errors[:title], "can't be blank"
  end

  test "validates description presence" do
    contribution = Contribution.new(
      user: @user,
      contribution_type: 'feature',
      title: 'Test'
    )

    assert_not contribution.valid?
    assert_includes contribution.errors[:description], "can't be blank"
  end

  test "approves contribution and sets stake value" do
    contribution = Contribution.create!(
      user: @user,
      contribution_type: 'feature',
      title: 'Add feature',
      description: 'New feature implementation'
    )

    reviewer = users(:two)
    contribution.approve!(reviewer, stake_value: 1500)

    assert contribution.approved?
    assert_equal reviewer, contribution.reviewed_by
    assert_equal 1500, contribution.stake_value
    assert_not_nil contribution.reviewed_at
  end

  test "approve without stake value uses default" do
    contribution = Contribution.create!(
      user: @user,
      contribution_type: 'bug_fix',
      title: 'Fix login bug',
      description: 'Fixed authentication issue'
    )

    reviewer = users(:two)
    contribution.approve!(reviewer)

    assert contribution.approved?
    assert_equal 500, contribution.stake_value # Default for bug_fix
  end

  test "rejects contribution with reason" do
    contribution = Contribution.create!(
      user: @user,
      contribution_type: 'feature',
      title: 'Add feature',
      description: 'New feature'
    )

    reviewer = users(:two)
    contribution.reject!(reviewer, reason: 'Does not meet quality standards')

    assert contribution.rejected?
    assert_equal 'Does not meet quality standards', contribution.review_notes
  end

  test "marks contribution as merged" do
    contribution = Contribution.create!(
      user: @user,
      contribution_type: 'code',
      title: 'Code contribution',
      description: 'Code changes',
      status: :approved,
      stake_value: 300
    )

    contribution.mark_merged!(external_reference: 'PR #123')

    assert contribution.merged?
    assert_equal 'PR #123', contribution.external_reference
    assert_not_nil contribution.merged_at
  end

  test "calculates default stake value with complexity multiplier" do
    contribution = Contribution.new(
      contribution_type: 'feature',
      complexity_multiplier: 2.0
    )

    # Base feature value is 1000, with 2x multiplier = 2000
    assert_equal 2000, contribution.calculate_default_stake_value
  end

  test "calculates default stake values for each type" do
    types_and_values = {
      'feature' => 1000,
      'bug_fix' => 500,
      'code' => 300,
      'documentation' => 200,
      'review' => 100,
      'support' => 150,
      'content' => 250,
      'community' => 100,
      'testing' => 200,
      'design' => 400
    }

    types_and_values.each do |type, expected_value|
      contribution = Contribution.new(contribution_type: type)
      assert_equal expected_value, contribution.calculate_default_stake_value, "Failed for #{type}"
    end
  end

  test "awards stake when approved" do
    contribution = Contribution.create!(
      user: @user,
      contribution_type: 'feature',
      title: 'New feature',
      description: 'Feature description'
    )

    reviewer = users(:two)
    contribution.approve!(reviewer, stake_value: 1000)

    # Trigger callback
    contribution.reload

    stake = TokenStake.find_by(source: contribution)
    assert_not_nil stake
    assert_equal 1000, stake.initial_amount
    assert_equal 'contribution', stake.stake_type
    assert_equal 'feature', stake.category
  end

  test "does not award stake twice" do
    contribution = Contribution.create!(
      user: @user,
      contribution_type: 'feature',
      title: 'New feature',
      description: 'Feature description'
    )

    reviewer = users(:two)
    contribution.approve!(reviewer, stake_value: 1000)
    contribution.reload # Reload to get the stake association

    initial_stake_count = TokenStake.where(source: contribution).count
    assert_equal 1, initial_stake_count, "Should have exactly 1 stake after approval"

    # Try to update again - should not create new stake
    contribution.update!(status: :merged)

    assert_equal initial_stake_count, TokenStake.where(source: contribution).count
  end

  test "stake_awarded? returns correct status" do
    contribution = Contribution.create!(
      user: @user,
      contribution_type: 'feature',
      title: 'New feature',
      description: 'Feature description'
    )

    assert_not contribution.stake_awarded?

    reviewer = users(:two)
    contribution.approve!(reviewer, stake_value: 1000)
    contribution.reload # Reload to get the stake association

    assert contribution.stake_awarded?
  end

  # === SCOPE TESTS ===

  test "code_contributions scope returns correct types" do
    Contribution.where(user: @user).destroy_all

    code = Contribution.create!(
      user: @user,
      contribution_type: 'code',
      title: 'Code',
      description: 'Code'
    )

    feature = Contribution.create!(
      user: @user,
      contribution_type: 'feature',
      title: 'Feature',
      description: 'Feature'
    )

    support = Contribution.create!(
      user: @user,
      contribution_type: 'support',
      title: 'Support',
      description: 'Support'
    )

    code_contributions = Contribution.for_user(@user).code_contributions

    assert_includes code_contributions, code
    assert_includes code_contributions, feature
    assert_not_includes code_contributions, support
  end

  test "leaderboard returns top contributors" do
    # Create some contributions for testing
    reviewer = users(:two)
    
    3.times do |i|
      Contribution.create!(
        user: @user,
        contribution_type: 'feature',
        title: "Feature #{i}",
        description: 'Feature',
        status: :approved,
        stake_value: 1000,
        reviewed_by: reviewer
      )
    end

    leaderboard = Contribution.leaderboard(limit: 10)
    
    assert leaderboard.any?
    assert_respond_to leaderboard.first, :contribution_count
    assert_respond_to leaderboard.first, :total_stake
  end
end
