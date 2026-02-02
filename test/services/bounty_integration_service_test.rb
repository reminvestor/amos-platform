# frozen_string_literal: true

require 'test_helper'

class BountyIntegrationServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @service = BountyIntegrationService.new(@entity)
  end

  # === TICKET → BOUNTY ===

  test "creates bounty from high priority ticket" do
    ticket = SupportTicket.create!(
      entity: @entity,
      title: 'Critical bug',
      description: 'App is crashing',
      source: 'log_monitor',
      priority: 'critical',
      category: 'bug'
    )

    # Mock the scorer
    AmosBountyScorer.stub(:score_ticket, ->(_) {
      { points: 200, rationale: 'Critical bug', effort_score: 5, impact_score: 8, urgency_score: 10, complexity_score: 6, estimated_hours: 4 }
    }) do
      bounty = @service.create_bounty_from_ticket(ticket)

      assert bounty.persisted?
      assert_equal ticket, bounty.support_ticket
      assert_equal 'bug', bounty.bounty_type
      assert_equal 200, bounty.points
      assert_equal 'support_ticket', bounty.source
    end
  end

  test "does not create duplicate bounty for ticket" do
    ticket = SupportTicket.create!(
      entity: @entity,
      title: 'Bug',
      description: 'Bug',
      source: 'log_monitor',
      priority: 'high',
      category: 'bug'
    )

    # Create existing bounty
    Bounty.create!(
      entity: @entity,
      support_ticket: ticket,
      title: ticket.title,
      bounty_type: 'bug',
      points: 100
    )

    AmosBountyScorer.stub(:score_ticket, ->(_) { { points: 100 } }) do
      result = @service.create_bounty_from_ticket(ticket)
      assert_nil result  # Should not create duplicate
    end
  end

  test "create_bounties_from_tickets processes high priority only" do
    # Low priority - should be ignored
    SupportTicket.create!(
      entity: @entity,
      title: 'Minor issue',
      description: 'Low priority',
      source: 'user_reported',
      priority: 'low',
      category: 'bug',
      status: 'open'
    )

    # High priority - should create bounty
    SupportTicket.create!(
      entity: @entity,
      title: 'Major issue',
      description: 'High priority',
      source: 'user_reported',
      priority: 'high',
      category: 'bug',
      status: 'open'
    )

    mock_score = { points: 150, rationale: 'Test', effort_score: 5, impact_score: 5, urgency_score: 5, complexity_score: 5, estimated_hours: 2 }
    
    AmosBountyScorer.stub(:score, mock_score) do
      bounties = @service.create_bounties_from_tickets!

      assert_equal 1, bounties.count
      assert_equal 'Major issue', bounties.first.title
    end
  end

  # === FEATURE REQUEST → BOUNTY ===

  test "creates bounty from approved feature with votes" do
    ticket = SupportTicket.create!(
      entity: @entity,
      title: 'New feature request',
      description: 'Users want this',
      source: 'user_reported',
      priority: 'medium',
      category: 'feature_request',
      admin_approved: true,
      metadata: { 'votes' => 5 }
    )

    AmosBountyScorer.stub(:score, ->(**_args) {
      { points: 200, rationale: 'Good feature', effort_score: 6, impact_score: 7, urgency_score: 5, complexity_score: 5, estimated_hours: 8 }
    }) do
      bounty = @service.create_bounty_from_feature_request(ticket, 5)

      assert bounty.persisted?
      assert_equal 'feature', bounty.bounty_type
      assert bounty.points > 200  # Should have vote bonus
      assert_equal 5, bounty.upvotes
      assert bounty.ai_scoring_rationale.include?('votes')
    end
  end

  test "ignores feature requests with insufficient votes" do
    SupportTicket.create!(
      entity: @entity,
      title: 'Feature',
      description: 'Feature',
      source: 'user_reported',
      category: 'feature_request',
      admin_approved: true,
      metadata: { 'votes' => 1 }  # Below MIN_VOTES_FOR_BOUNTY
    )

    bounties = @service.create_bounties_from_feature_requests!
    assert_empty bounties
  end

  # === BOUNTY COMPLETION SYNC ===

  test "sync_bounty_completion resolves linked ticket" do
    ticket = SupportTicket.create!(
      entity: @entity,
      title: 'Bug to fix',
      description: 'Fix needed',
      source: 'log_monitor',
      priority: 'high',
      category: 'bug'
    )

    user = users(:one)
    bounty = Bounty.create!(
      entity: @entity,
      support_ticket: ticket,
      title: 'Fix bug',
      bounty_type: 'bug',
      points: 100,
      claimed_by: user
    )

    @service.sync_bounty_completion!(bounty)

    ticket.reload
    assert_equal 'resolved', ticket.status
  end

  # === SYNC ALL ===

  test "sync_all creates bounties from all sources" do
    # Create a high-priority ticket
    SupportTicket.create!(
      entity: @entity,
      title: 'Critical bug',
      description: 'Fix ASAP',
      source: 'log_monitor',
      priority: 'critical',
      category: 'bug',
      status: 'open'
    )

    mock_score = { points: 200, rationale: 'Test', effort_score: 5, impact_score: 8, urgency_score: 10, complexity_score: 6, estimated_hours: 4 }
    
    AmosBountyScorer.stub :score, mock_score do
      results = @service.sync_all!

      assert results[:from_tickets].any?
    end
  end
end
