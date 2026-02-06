# frozen_string_literal: true

require 'test_helper'

class SupportTicketReadinessTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # READINESS LABEL
  # ═══════════════════════════════════════════════════════════════════════════

  test "readiness_label returns correct labels for each range" do
    ticket = SupportTicket.new(entity: @entity)

    { 0 => 'Insufficient', 15 => 'Insufficient', 30 => 'Insufficient',
      35 => 'Partial', 50 => 'Partial',
      55 => 'Good', 70 => 'Good',
      75 => 'Strong', 90 => 'Strong',
      95 => 'Excellent', 100 => 'Excellent' }.each do |score, expected|
      ticket.readiness_score = score
      assert_equal expected, ticket.readiness_label, "Score #{score} should be '#{expected}'"
    end
  end

  test "readiness_label handles nil score" do
    ticket = SupportTicket.new(entity: @entity, readiness_score: nil)
    assert_equal 'Insufficient', ticket.readiness_label
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # BOUNTY READY
  # ═══════════════════════════════════════════════════════════════════════════

  test "bounty_ready? returns true for eligible high-readiness ticket" do
    ticket = SupportTicket.new(
      entity: @entity,
      bounty_eligible: true,
      readiness_score: 75
    )
    assert ticket.bounty_ready?
  end

  test "bounty_ready? returns false for low readiness" do
    ticket = SupportTicket.new(
      entity: @entity,
      bounty_eligible: true,
      readiness_score: 30
    )
    assert_not ticket.bounty_ready?
  end

  test "bounty_ready? returns false when not eligible" do
    ticket = SupportTicket.new(
      entity: @entity,
      bounty_eligible: false,
      readiness_score: 90
    )
    assert_not ticket.bounty_ready?
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SCOPES
  # ═══════════════════════════════════════════════════════════════════════════

  test "bounty_eligible scope returns only eligible tickets" do
    eligible = SupportTicket.create!(
      entity: @entity, title: 'Eligible', description: 'Test',
      source: 'user_reported', priority: 'high', category: 'bug',
      bounty_eligible: true, readiness_score: 80
    )
    not_eligible = SupportTicket.create!(
      entity: @entity, title: 'Not eligible', description: 'Test',
      source: 'user_reported', priority: 'low', category: 'bug',
      bounty_eligible: false, readiness_score: 20
    )

    results = SupportTicket.bounty_eligible
    assert_includes results, eligible
    assert_not_includes results, not_eligible
  end

  test "needs_qualification scope returns unassessed tickets" do
    assessed = SupportTicket.create!(
      entity: @entity, title: 'Assessed', description: 'Test',
      source: 'user_reported', priority: 'medium', category: 'bug',
      readiness_assessed_at: Time.current
    )
    unassessed = SupportTicket.create!(
      entity: @entity, title: 'Unassessed', description: 'Test',
      source: 'user_reported', priority: 'medium', category: 'bug',
      readiness_assessed_at: nil
    )

    results = SupportTicket.needs_qualification
    assert_includes results, unassessed
    assert_not_includes results, assessed
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FEATURE REQUEST HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  test "is_feature_request? returns true for feature requests" do
    ticket = SupportTicket.new(category: 'feature_request')
    assert ticket.is_feature_request?
    assert_not ticket.is_bug?
  end

  test "is_bug? returns true for bugs" do
    ticket = SupportTicket.new(category: 'bug')
    assert ticket.is_bug?
    assert_not ticket.is_feature_request?
  end
end
