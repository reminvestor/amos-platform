# frozen_string_literal: true

require 'test_helper'

class GithubWebhookServiceTest < ActiveSupport::TestCase
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
    bounty = GithubWebhookService.send(:find_linked_bounty,
      "Fix email system - Bounty ##{@bounty.id}",
      "Some description",
      "fix/email-system"
    )
    assert_equal @bounty, bounty
  end

  test "finds bounty from PR body with Fixes bounty pattern" do
    bounty = GithubWebhookService.send(:find_linked_bounty,
      "Fix email system",
      "This PR fixes bounty ##{@bounty.id} by updating the mailer config",
      "fix/email-system"
    )
    assert_equal @bounty, bounty
  end

  test "finds bounty from branch name" do
    bounty = GithubWebhookService.send(:find_linked_bounty,
      "Fix email system",
      "Some description",
      "bounty-#{@bounty.id}/fix-email"
    )
    assert_equal @bounty, bounty
  end

  test "finds bounty via ticket number" do
    # Link bounty to ticket first
    @bounty.update!(support_ticket: @ticket)

    bounty = GithubWebhookService.send(:find_linked_bounty,
      "Fix: #{@ticket.ticket_number} Email broken",
      "Resolves the email issue",
      "fix/email"
    )
    assert_equal @bounty, bounty
  end

  test "returns nil when no bounty reference found" do
    bounty = GithubWebhookService.send(:find_linked_bounty,
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
    ticket = GithubWebhookService.send(:find_linked_ticket,
      "Fix: #{@ticket.ticket_number} Email notification bug",
      "Description"
    )
    assert_equal @ticket, ticket
  end

  test "returns nil when no ticket reference found" do
    ticket = GithubWebhookService.send(:find_linked_ticket,
      "Update README",
      "Description"
    )
    assert_nil ticket
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PR OPENED EVENT
  # ═══════════════════════════════════════════════════════════════════════════

  test "process handles PR opened event without error" do
    payload = build_pr_payload(action: 'opened', pr_number: 42, title: "Fix email system")
    assert_nothing_raised { GithubWebhookService.process(event_type: 'pull_request', payload: payload) }
  end

  test "process handles PR merged event without error" do
    payload = build_pr_payload(action: 'closed', pr_number: 42, title: "Fix email", merged: true, merge_sha: 'abc123')
    assert_nothing_raised { GithubWebhookService.process(event_type: 'pull_request', payload: payload) }
  end

  test "process handles PR closed event without error" do
    payload = build_pr_payload(action: 'closed', pr_number: 42, title: "Fix email", merged: false)
    assert_nothing_raised { GithubWebhookService.process(event_type: 'pull_request', payload: payload) }
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
      GithubWebhookService.process(event_type: 'pull_request_review', payload: payload)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PING EVENT
  # ═══════════════════════════════════════════════════════════════════════════

  test "handles ping event without error" do
    assert_nothing_raised do
      GithubWebhookService.process(event_type: 'ping', payload: { 'zen' => 'Speak like a human.' })
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # UNKNOWN EVENTS
  # ═══════════════════════════════════════════════════════════════════════════

  test "ignores unknown event types" do
    assert_nothing_raised do
      GithubWebhookService.process(event_type: 'star', payload: { 'action' => 'created' })
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # BOUNTY PATTERNS
  # ═══════════════════════════════════════════════════════════════════════════

  test "all bounty patterns match expected formats" do
    patterns = GithubWebhookService::BOUNTY_PATTERNS

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
