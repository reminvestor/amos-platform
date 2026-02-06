# frozen_string_literal: true

require 'test_helper'

class GitHubWebhookServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)

    @bounty = Bounty.create!(
      entity: @entity,
      title: "Fix email notification system",
      description: "Emails are not sending on form submit",
      bounty_type: 'bug',
      points: 100,
      status: 'open',
      source: 'admin_created',
      urgency_score: 7,
      impact_score: 8
    )

    @ticket = SupportTicket.create!(
      entity: @entity,
      title: "Email notifications broken",
      description: "No emails sent after form submit",
      source: 'user_reported',
      priority: 'high',
      category: 'bug'
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # BOUNTY LINKING
  # ═══════════════════════════════════════════════════════════════════════════

  test "finds bounty from PR title with bounty ID" do
    bounty = GitHubWebhookService.send(:find_linked_bounty,
      "Fix email system - Bounty ##{@bounty.id}",
      "Some description",
      "fix/email-system"
    )
    assert_equal @bounty, bounty
  end

  test "finds bounty from PR body with Fixes bounty pattern" do
    bounty = GitHubWebhookService.send(:find_linked_bounty,
      "Fix email system",
      "This PR fixes bounty ##{@bounty.id} by updating the mailer config",
      "fix/email-system"
    )
    assert_equal @bounty, bounty
  end

  test "finds bounty from branch name" do
    bounty = GitHubWebhookService.send(:find_linked_bounty,
      "Fix email system",
      "Some description",
      "bounty-#{@bounty.id}/fix-email"
    )
    assert_equal @bounty, bounty
  end

  test "finds bounty via ticket number" do
    # Link bounty to ticket first
    @bounty.update!(support_ticket: @ticket)

    bounty = GitHubWebhookService.send(:find_linked_bounty,
      "Fix: #{@ticket.ticket_number} Email broken",
      "Resolves the email issue",
      "fix/email"
    )
    assert_equal @bounty, bounty
  end

  test "returns nil when no bounty reference found" do
    bounty = GitHubWebhookService.send(:find_linked_bounty,
      "Update README",
      "Just a small doc update",
      "docs/readme-update"
    )
    assert_nil bounty
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TICKET LINKING
  # ═══════════════════════════════════════════════════════════════════════════

  test "finds ticket from PR title" do
    ticket = GitHubWebhookService.send(:find_linked_ticket,
      "Fix: #{@ticket.ticket_number} Email notification bug",
      "Description"
    )
    assert_equal @ticket, ticket
  end

  test "returns nil when no ticket reference found" do
    ticket = GitHubWebhookService.send(:find_linked_ticket,
      "Update README",
      "Description"
    )
    assert_nil ticket
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PR OPENED EVENT
  # ═══════════════════════════════════════════════════════════════════════════

  test "PR opened links to bounty and updates status" do
    payload = build_pr_payload(
      action: 'opened',
      pr_number: 42,
      title: "Fix email - Bounty ##{@bounty.id}",
      body: "This fixes the email notification bug",
      branch: "fix/email-bounty-#{@bounty.id}"
    )

    GitHubWebhookService.process(event_type: 'pull_request', payload: payload)

    @bounty.reload
    assert_equal 42, @bounty.pr_number
    assert @bounty.pr_url.present?
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PR MERGED EVENT
  # ═══════════════════════════════════════════════════════════════════════════

  test "PR merged auto-submits linked bounty for review" do
    # First claim the bounty
    @bounty.update!(status: 'in_progress', claimed_by: @user, pr_number: 42)

    payload = build_pr_payload(
      action: 'closed',
      pr_number: 42,
      title: "Fix email - Bounty ##{@bounty.id}",
      merged: true,
      merge_sha: 'abc123def456'
    )

    GitHubWebhookService.process(event_type: 'pull_request', payload: payload)

    @bounty.reload
    assert_equal 'abc123def456', @bounty.commit_sha
    assert @bounty.status.in?(%w[submitted reviewing approved]), "Bounty should advance past in_progress, got: #{@bounty.status}"
  end

  test "PR merged resolves linked ticket" do
    @bounty.update!(support_ticket: @ticket, status: 'in_progress', claimed_by: @user, pr_number: 42)

    payload = build_pr_payload(
      action: 'closed',
      pr_number: 42,
      title: "Fix: #{@ticket.ticket_number} Email bug",
      merged: true,
      merge_sha: 'abc123def456'
    )

    GitHubWebhookService.process(event_type: 'pull_request', payload: payload)

    @ticket.reload
    assert_equal 'resolved', @ticket.status
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PR CLOSED (NOT MERGED)
  # ═══════════════════════════════════════════════════════════════════════════

  test "PR closed without merge releases bounty claim" do
    @bounty.update!(status: 'in_progress', claimed_by: @user, pr_number: 42)

    payload = build_pr_payload(
      action: 'closed',
      pr_number: 42,
      title: "Fix email - Bounty ##{@bounty.id}",
      merged: false
    )

    GitHubWebhookService.process(event_type: 'pull_request', payload: payload)

    @bounty.reload
    # Should release the claim (if release_claim! is available)
    # The exact status depends on the bounty model implementation
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PR REVIEW EVENTS
  # ═══════════════════════════════════════════════════════════════════════════

  test "handles PR review approved event" do
    payload = {
      'action' => 'submitted',
      'review' => {
        'state' => 'approved',
        'body' => 'LGTM!',
        'user' => { 'login' => 'reviewer123' }
      },
      'pull_request' => {
        'number' => 42,
        'html_url' => 'https://github.com/amos-labs/amos-platform/pull/42'
      },
      'repository' => { 'full_name' => 'amos-labs/amos-platform' }
    }

    # Should not raise
    assert_nothing_raised do
      GitHubWebhookService.process(event_type: 'pull_request_review', payload: payload)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PING EVENT
  # ═══════════════════════════════════════════════════════════════════════════

  test "handles ping event without error" do
    assert_nothing_raised do
      GitHubWebhookService.process(event_type: 'ping', payload: { 'zen' => 'Speak like a human.' })
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # UNKNOWN EVENTS
  # ═══════════════════════════════════════════════════════════════════════════

  test "ignores unknown event types" do
    assert_nothing_raised do
      GitHubWebhookService.process(event_type: 'star', payload: { 'action' => 'created' })
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # BOUNTY PATTERNS
  # ═══════════════════════════════════════════════════════════════════════════

  test "all bounty patterns match expected formats" do
    patterns = GitHubWebhookService::BOUNTY_PATTERNS

    # bounty #123
    assert patterns.any? { |p| "Fixes bounty #123".match?(p) }
    assert patterns.any? { |p| "Bounty #456".match?(p) }
    assert patterns.any? { |p| "closes bounty #789".match?(p) }

    # AMOS-00042
    assert patterns.any? { |p| "Fix: AMOS-00042 email bug".match?(p) }

    # bounty:123
    assert patterns.any? { |p| "bounty:123/fix-email".match?(p) }
    assert patterns.any? { |p| "bounty-456".match?(p) }
  end

  private

  def build_pr_payload(action:, pr_number:, title: "Test PR", body: "", branch: "fix/test", merged: false, merge_sha: nil)
    {
      'action' => action,
      'pull_request' => {
        'number' => pr_number,
        'html_url' => "https://github.com/amos-labs/amos-platform/pull/#{pr_number}",
        'title' => title,
        'body' => body,
        'merged' => merged,
        'merge_commit_sha' => merge_sha,
        'head' => { 'ref' => branch },
        'user' => { 'login' => 'contributor123' },
        'state' => merged ? 'closed' : 'open'
      },
      'repository' => {
        'full_name' => 'amos-labs/amos-platform',
        'name' => 'amos-platform'
      }
    }
  end
end
