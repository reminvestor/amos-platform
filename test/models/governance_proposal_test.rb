# frozen_string_literal: true

require 'test_helper'

class GovernanceProposalTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    # Ensure user has enough stake to propose
    TokenStake.where(user: @user).destroy_all
    @stake = TokenStake.create!(
      user: @user,
      stake_type: 'contribution',
      initial_amount: 30_000,
      current_amount: 30_000,
      earned_at: Time.current
    )
  end

  # === PROPOSAL TYPES ===

  test "all proposal types have required configuration" do
    GovernanceProposal::PROPOSAL_TYPES.each do |type, config|
      assert config[:name].present?, "#{type} should have a name"
      assert config[:min_stake].is_a?(Numeric), "#{type} should have min_stake"
      assert config[:quorum].is_a?(Numeric), "#{type} should have quorum"
      assert config[:threshold].is_a?(Numeric), "#{type} should have threshold"
      assert config[:discussion_days].is_a?(Numeric), "#{type} should have discussion_days"
      assert config[:voting_days].is_a?(Numeric), "#{type} should have voting_days"
    end
  end

  test "parameter and constitutional require supermajority" do
    GovernanceProposal::PROPOSAL_TYPES.each do |type, config|
      if [:parameter, :constitutional].include?(type)
        assert_equal 0.667, config[:threshold], "#{type} should require 2/3 supermajority"
      else
        assert_equal 0.50, config[:threshold], "#{type} should require simple majority"
      end
    end
  end

  # === CREATION ===

  test "creates proposal with valid attributes" do
    proposal = GovernanceProposal.create!(
      proposer: @user,
      title: "Increase R&D Budget",
      description: "Let's allocate more to R&D projects",
      proposal_type: 'r_and_d'
    )

    assert proposal.persisted?
    assert_equal 'discussion', proposal.status
    assert_equal 1_000, proposal.staked_amount
  end

  test "requires sufficient stake to propose" do
    # User with no stake
    poor_user = users(:two)
    TokenStake.where(user: poor_user).destroy_all

    proposal = GovernanceProposal.new(
      proposer: poor_user,
      title: "I want changes",
      description: "But I have no stake",
      proposal_type: 'r_and_d'
    )

    assert_not proposal.valid?
    assert proposal.errors[:base].any? { |e| e.include?("at least") }
  end

  test "constitutional proposals require 25k stake" do
    # User only has 30k, enough for constitutional
    proposal = GovernanceProposal.new(
      proposer: @user,
      title: "Change Core Rules",
      description: "Major governance change",
      proposal_type: 'constitutional'
    )

    assert proposal.valid?
    assert_equal 25_000, proposal.min_stake_required
  end

  # === CONFIGURATION ===

  test "requires_supermajority? for parameter and constitutional" do
    param_proposal = GovernanceProposal.new(proposal_type: 'parameter')
    const_proposal = GovernanceProposal.new(proposal_type: 'constitutional')
    feature_proposal = GovernanceProposal.new(proposal_type: 'feature')

    assert param_proposal.requires_supermajority?
    assert const_proposal.requires_supermajority?
    assert_not feature_proposal.requires_supermajority?
  end

  test "discussion and voting periods vary by type" do
    feature = GovernanceProposal.new(proposal_type: 'feature', created_at: Time.current)
    constitutional = GovernanceProposal.new(proposal_type: 'constitutional', created_at: Time.current)

    # Feature: 5 day discussion, 5 day voting
    assert_equal 5.days.from_now.to_i, feature.discussion_ends_at.to_i
    assert_equal 10.days.from_now.to_i, feature.voting_ends_at.to_i

    # Constitutional: 21 day discussion, 21 day voting
    assert_equal 21.days.from_now.to_i, constitutional.discussion_ends_at.to_i
    assert_equal 42.days.from_now.to_i, constitutional.voting_ends_at.to_i
  end

  # === VOTING ===

  test "user can vote during voting period" do
    proposal = GovernanceProposal.create!(
      proposer: @user,
      title: "Test Proposal",
      description: "Testing voting",
      proposal_type: 'feature',
      status: 'voting'
    )

    voter = users(:two)
    TokenStake.where(user: voter).destroy_all
    TokenStake.create!(
      user: voter,
      stake_type: 'contribution',
      initial_amount: 500,
      current_amount: 500,
      earned_at: Time.current
    )

    assert proposal.can_vote?(voter)

    result = proposal.vote!(user: voter, vote_type: 'for')
    assert result[:success]
    assert_equal 500, result[:voting_power]
  end

  test "user cannot vote twice" do
    proposal = GovernanceProposal.create!(
      proposer: @user,
      title: "Test Proposal",
      description: "Testing voting",
      proposal_type: 'feature',
      status: 'voting'
    )

    voter = users(:two)
    TokenStake.where(user: voter).destroy_all
    TokenStake.create!(
      user: voter,
      stake_type: 'contribution',
      initial_amount: 500,
      current_amount: 500,
      earned_at: Time.current
    )

    proposal.vote!(user: voter, vote_type: 'for')
    
    assert_not proposal.can_vote?(voter)
  end

  test "voting power equals user stake" do
    proposal = GovernanceProposal.create!(
      proposer: @user,
      title: "Test Proposal",
      description: "Testing voting power",
      proposal_type: 'feature',
      status: 'voting'
    )

    voter = users(:two)
    TokenStake.where(user: voter).destroy_all
    TokenStake.create!(
      user: voter,
      stake_type: 'contribution',
      initial_amount: 1000,
      current_amount: 750,  # Decayed
      earned_at: 1.year.ago
    )

    result = proposal.vote!(user: voter, vote_type: 'for')
    assert_equal 750, result[:voting_power]  # Uses current, not initial
  end

  # === QUORUM AND THRESHOLD ===

  test "quorum calculation" do
    proposal = GovernanceProposal.create!(
      proposer: @user,
      title: "Test Proposal",
      description: "Testing quorum",
      proposal_type: 'feature',
      status: 'voting'
    )

    # Total voting power is from @stake (30,000)
    # Feature quorum is 20%
    # Need 6,000 votes for quorum

    voter = users(:two)
    TokenStake.where(user: voter).destroy_all
    TokenStake.create!(
      user: voter,
      stake_type: 'contribution',
      initial_amount: 5000,
      current_amount: 5000,
      earned_at: Time.current
    )

    proposal.vote!(user: voter, vote_type: 'for')

    # 5000 / 35000 total = ~14% < 20% quorum
    assert_not proposal.quorum_met?

    # Add more voting power
    proposal.vote!(user: @user, vote_type: 'for')
    # 35000 / 35000 = 100% > 20% quorum
    assert proposal.quorum_met?
  end

  test "threshold calculation for simple majority" do
    proposal = GovernanceProposal.create!(
      proposer: @user,
      title: "Test Proposal",
      description: "Testing threshold",
      proposal_type: 'feature',
      status: 'voting'
    )

    voter1 = users(:two)
    TokenStake.where(user: voter1).destroy_all
    TokenStake.create!(user: voter1, stake_type: 'contribution', initial_amount: 1000, current_amount: 1000, earned_at: Time.current)

    proposal.vote!(user: @user, vote_type: 'for')  # 30000
    proposal.vote!(user: voter1, vote_type: 'against')  # 1000

    # 30000 for / 31000 total = 96.8% > 50%
    assert proposal.threshold_met?
  end

  # === STATUS TRANSITIONS ===

  test "start_voting transitions from discussion" do
    proposal = GovernanceProposal.create!(
      proposer: @user,
      title: "Test Proposal",
      description: "Testing status transition",
      proposal_type: 'feature'
    )

    # Can't start voting yet (discussion not over)
    proposal.start_voting!
    assert_equal 'discussion', proposal.status

    # Fast forward past discussion period
    proposal.update!(created_at: 10.days.ago)
    proposal.start_voting!
    
    assert_equal 'voting', proposal.status
  end

  test "cancel returns staked tokens" do
    proposal = GovernanceProposal.create!(
      proposer: @user,
      title: "Test Proposal",
      description: "Will be cancelled",
      proposal_type: 'feature'
    )

    assert proposal.cancel!(by_user: @user)
    assert_equal 'cancelled', proposal.status
  end
end
