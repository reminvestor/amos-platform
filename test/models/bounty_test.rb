# frozen_string_literal: true

require 'test_helper'

class BountyTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @reviewer = users(:two)
  end

  # === CREATION ===

  test "creates bounty with valid attributes" do
    bounty = Bounty.new(
      entity: @entity,
      title: 'Fix login bug',
      description: 'Users cannot log in on mobile',
      bounty_type: 'bug',
      points: 100
    )

    assert bounty.valid?
    assert bounty.save
    assert_equal 'open', bounty.status
    assert_equal 'amos_thinking', bounty.source  # No created_by = AMOS
  end

  test "creates bounty from AMOS" do
    bounty = Bounty.create_from_amos!(
      entity: @entity,
      title: 'Add dark mode',
      description: 'Users want dark mode support',
      bounty_type: 'feature',
      points: 250,
      scoring_rationale: 'Medium effort, high impact',
      metadata: { priority: 'medium' }
    )

    assert bounty.persisted?
    assert_nil bounty.created_by
    assert bounty.created_by_amos?
    assert_equal 'amos_thinking', bounty.source
    assert_equal 250, bounty.points
  end

  test "creates bounty from support ticket" do
    ticket = SupportTicket.create!(
      entity: @entity,
      title: 'Critical login failure',
      description: 'Login broken for all users',
      source: 'log_monitor',
      priority: 'critical',
      category: 'bug'
    )

    bounty = Bounty.create_from_ticket!(
      ticket,
      points: 200,
      scoring_rationale: 'Critical bug affecting all users'
    )

    assert bounty.persisted?
    assert_equal ticket, bounty.support_ticket
    assert_equal 'support_ticket', bounty.source
    assert_equal 'bug', bounty.bounty_type
    assert_equal 10, bounty.urgency_score  # Critical = 10
  end

  # === VALIDATIONS ===

  test "validates bounty type is valid" do
    bounty = Bounty.new(
      entity: @entity,
      title: 'Test',
      description: 'Test',
      bounty_type: 'invalid_type',
      points: 100
    )

    assert_not bounty.valid?
    assert_includes bounty.errors[:bounty_type], 'is not included in the list'
  end

  test "validates points are positive" do
    bounty = Bounty.new(
      entity: @entity,
      title: 'Test',
      description: 'Test',
      bounty_type: 'bug',
      points: 0
    )

    assert_not bounty.valid?
    assert bounty.errors[:points].any?
  end

  test "validates pr_url format" do
    bounty = Bounty.new(
      entity: @entity,
      title: 'Test',
      bounty_type: 'bug',
      points: 100,
      pr_url: 'not-a-url'
    )

    assert_not bounty.valid?
    assert bounty.errors[:pr_url].any?
  end

  # === STATUS TRANSITIONS ===

  test "claim bounty" do
    bounty = create_open_bounty

    result = bounty.claim!(@user)

    assert result
    assert_equal 'claimed', bounty.status
    assert_equal @user, bounty.claimed_by
    assert_not_nil bounty.claimed_at
  end

  test "cannot claim already claimed bounty" do
    bounty = create_open_bounty
    bounty.claim!(@user)

    other_user = users(:three)
    result = bounty.claim!(other_user)

    assert_not result
    assert_equal @user, bounty.claimed_by  # Still original claimer
  end

  test "start work on claimed bounty" do
    bounty = create_open_bounty
    bounty.claim!(@user)

    result = bounty.start_work!

    assert result
    assert_equal 'in_progress', bounty.status
  end

  test "submit work with evidence" do
    bounty = create_open_bounty
    bounty.claim!(@user)
    bounty.start_work!

    result = bounty.submit!(
      notes: 'Fixed the bug by correcting the OAuth flow',
      pr_url: 'https://github.com/org/repo/pull/123',
      commit_sha: 'abc123def456'
    )

    assert result
    assert_equal 'submitted', bounty.status
    assert_equal 'https://github.com/org/repo/pull/123', bounty.pr_url
    assert_equal 123, bounty.pr_number
    assert_equal 'abc123def456', bounty.commit_sha
    assert_not_nil bounty.submitted_at
  end

  test "submit work with non-code artifacts" do
    bounty = create_open_bounty(bounty_type: 'content', title: 'Write blog post')
    bounty.claim!(@user)

    bounty.submit!(
      notes: 'Published the blog post',
      work_url: 'https://blog.example.com/my-post',
      artifacts: [
        { url: 'https://youtube.com/watch?v=123', type: 'video', description: 'Tutorial' }
      ]
    )

    assert_equal 'https://blog.example.com/my-post', bounty.work_url
    assert_equal 1, bounty.work_artifacts.count
  end

  test "approve bounty creates contribution" do
    bounty = create_submitted_bounty

    assert_difference 'Contribution.count', 1 do
      bounty.approve!(reviewer: @reviewer, final_points: 120, notes: 'Great work!')
    end

    assert_equal 'approved', bounty.status
    assert_equal 120, bounty.final_points
    assert_not_nil bounty.approved_at

    contribution = Contribution.last
    assert_equal @user, contribution.user
    assert_equal 120, contribution.stake_value
    assert contribution.external_reference.include?('bounty:')
  end

  test "reject bounty releases claim" do
    bounty = create_submitted_bounty

    bounty.reject!(reviewer: @reviewer, notes: 'Does not meet requirements')

    assert_equal 'open', bounty.status  # Released for others
    assert_nil bounty.claimed_by
    assert_nil bounty.claimed_at
  end

  # === WORK EVIDENCE ===

  test "extracts PR number from GitHub URL" do
    bounty = create_open_bounty
    bounty.claim!(@user)

    bounty.submit!(
      notes: 'Done',
      pr_url: 'https://github.com/NuvolaNetworks/agent_marketing/pull/456'
    )

    assert_equal 456, bounty.pr_number
  end

  test "extracts PR number from GitLab URL" do
    bounty = create_open_bounty
    bounty.claim!(@user)

    bounty.submit!(
      notes: 'Done',
      pr_url: 'https://gitlab.com/org/repo/-/merge_requests/789'
    )

    assert_equal 789, bounty.pr_number
  end

  test "work evidence summary" do
    bounty = create_open_bounty
    bounty.claim!(@user)
    bounty.submit!(
      notes: 'Done',
      pr_url: 'https://github.com/org/repo/pull/123',
      commit_sha: 'abc123def456789'
    )

    summary = bounty.work_evidence_summary

    assert summary.include?('PR:')
    assert summary.include?('Commit: abc123de')  # Truncated
  end

  # === QUERIES ===

  test "effective_points returns final_points when set" do
    bounty = create_open_bounty(points: 100)
    bounty.update!(final_points: 120)

    assert_equal 120, bounty.effective_points
  end

  test "effective_points falls back to points" do
    bounty = create_open_bounty(points: 100)

    assert_equal 100, bounty.effective_points
  end

  test "expired? returns true when past expiration" do
    bounty = create_open_bounty
    bounty.update!(expires_at: 1.day.ago)

    assert bounty.expired?
    assert_not bounty.can_claim?
  end

  test "created_by_amos? returns true when no creator" do
    bounty = create_open_bounty
    assert bounty.created_by_amos?

    bounty.update!(created_by: @user)
    assert_not bounty.created_by_amos?
  end

  # === VOTING ===

  test "upvote increases count" do
    bounty = create_open_bounty

    assert_difference -> { bounty.reload.upvotes }, 1 do
      bounty.upvote!
    end
  end

  test "vote_score calculates difference" do
    bounty = create_open_bounty
    bounty.update!(upvotes: 10, downvotes: 3)

    assert_equal 7, bounty.vote_score
  end

  # === SCOPES ===

  test "available scope excludes expired" do
    open_bounty = create_open_bounty
    expired_bounty = create_open_bounty(title: 'Expired')
    expired_bounty.update!(expires_at: 1.day.ago)

    available = Bounty.available

    assert_includes available, open_bounty
    assert_not_includes available, expired_bounty
  end

  test "high_value scope returns bounties >= 200 points" do
    low = create_open_bounty(points: 50)
    high = create_open_bounty(points: 300, title: 'High value')

    high_value = Bounty.high_value

    assert_includes high_value, high
    assert_not_includes high_value, low
  end

  private

  def create_open_bounty(attrs = {})
    Bounty.create!({
      entity: @entity,
      title: 'Test bounty',
      description: 'Test description',
      bounty_type: 'bug',
      points: 100
    }.merge(attrs))
  end

  def create_submitted_bounty
    bounty = create_open_bounty
    bounty.claim!(@user)
    bounty.submit!(notes: 'Done', pr_url: 'https://github.com/org/repo/pull/1')
    bounty
  end
end
