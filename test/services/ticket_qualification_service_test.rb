# frozen_string_literal: true

require 'test_helper'

class TicketQualificationServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # READINESS SCORING
  # ═══════════════════════════════════════════════════════════════════════════

  test "well-defined ticket scores high readiness" do
    ticket = create_rich_ticket

    result = TicketQualificationService.assess(ticket)

    assert result[:score] >= 70, "Rich ticket should score 70+, got #{result[:score]}"
    assert result[:gaps].count < 3, "Rich ticket should have few gaps"
    assert result[:strengths].any?, "Rich ticket should have strengths"
  end

  test "minimal ticket scores low readiness" do
    ticket = SupportTicket.create!(
      entity: @entity,
      title: "bug",
      description: "broken",
      source: 'user_reported',
      priority: 'medium',
      category: 'bug'
    )

    result = TicketQualificationService.assess(ticket)

    assert result[:score] < 40, "Minimal ticket should score below 40, got #{result[:score]}"
    assert result[:gaps].count > 3, "Minimal ticket should have many gaps"
  end

  test "ticket with just title and description scores partial" do
    ticket = SupportTicket.create!(
      entity: @entity,
      title: "Email notifications not sending after contact form submission",
      description: "When a user submits the contact form on the landing page, they should receive a confirmation email but nothing is being sent. This has been happening since the last deployment.",
      source: 'user_reported',
      priority: 'high',
      category: 'bug'
    )

    result = TicketQualificationService.assess(ticket)

    assert result[:score].between?(25, 60), "Partial ticket should score 25-60, got #{result[:score]}"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TITLE QUALITY
  # ═══════════════════════════════════════════════════════════════════════════

  test "specific title gets high quality score" do
    score = TicketQualificationService.send(:assess_title_quality, "Fix email notification delay on contact form submission page")
    assert score >= 0.6, "Specific title should score 0.6+, got #{score}"
  end

  test "vague title gets low quality score" do
    score = TicketQualificationService.send(:assess_title_quality, "bug")
    assert score <= 0.3, "Vague title 'bug' should score 0.3 or less, got #{score}"
  end

  test "empty title gets zero quality score" do
    score = TicketQualificationService.send(:assess_title_quality, "")
    assert_equal 0.0, score
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # DESCRIPTION QUALITY
  # ═══════════════════════════════════════════════════════════════════════════

  test "detailed description gets high quality score" do
    desc = "When navigating to the dashboard page and clicking on 'Analytics',\nthe page shows a blank white screen.\n- Expected: Analytics charts should load\n- Actual: 500 error in console\n\nURL: https://app.example.com/dashboard/analytics"
    score = TicketQualificationService.send(:assess_description_quality, desc)
    assert score >= 0.6, "Detailed description should score 0.6+, got #{score}"
  end

  test "thin description gets low quality score" do
    score = TicketQualificationService.send(:assess_description_quality, "it's broken")
    assert score <= 0.2, "Thin description should score low, got #{score}"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SYSTEM ENRICHMENT
  # ═══════════════════════════════════════════════════════════════════════════

  test "auto-enriches component from error file" do
    ticket = SupportTicket.create!(
      entity: @entity,
      title: "API error on contact create",
      description: "500 error when creating contacts",
      source: 'log_monitor',
      priority: 'high',
      category: 'bug',
      error_file: 'app/controllers/api/v1/contacts_controller.rb',
      error_message: 'NoMethodError: undefined method'
    )

    enrichments = TicketQualificationService.send(:enrich_from_system, ticket)

    assert enrichments.any? { |e| e.include?('affected component') }, "Should set affected component"
    assert_equal 'API', ticket.affected_component
  end

  test "auto-enriches actual behavior from error message" do
    ticket = SupportTicket.create!(
      entity: @entity,
      title: "Dashboard crash",
      description: "Dashboard is crashing on load",
      source: 'log_monitor',
      priority: 'high',
      category: 'bug',
      error_message: 'TypeError: Cannot read property of undefined'
    )

    enrichments = TicketQualificationService.send(:enrich_from_system, ticket)

    assert enrichments.any? { |e| e.include?('actual behavior') }, "Should set actual behavior"
    assert ticket.actual_behavior.include?('TypeError')
  end

  test "auto-enriches environment info" do
    ticket = SupportTicket.create!(
      entity: @entity,
      title: "Test ticket",
      description: "Test description for environment enrichment",
      source: 'user_reported',
      priority: 'medium',
      category: 'bug'
    )

    TicketQualificationService.send(:enrich_from_system, ticket)

    assert ticket.environment_info.present?
    assert ticket.environment_info['rails_env'].present?
  end

  test "auto-estimates effort based on priority" do
    ticket = SupportTicket.create!(
      entity: @entity,
      title: "Critical production issue",
      description: "Production database connection failing",
      source: 'log_monitor',
      priority: 'critical',
      category: 'bug'
    )

    TicketQualificationService.send(:enrich_from_system, ticket)

    assert_equal 'small', ticket.estimated_effort, "Critical bugs should be estimated as small (fast fix)"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # QUALIFICATION (FULL PIPELINE)
  # ═══════════════════════════════════════════════════════════════════════════

  test "qualify! sets readiness score and assessed timestamp" do
    ticket = create_rich_ticket

    result = TicketQualificationService.qualify!(ticket, auto_enrich: true)

    assert ticket.readiness_score > 0
    assert ticket.readiness_assessed_at.present?
    assert ticket.readiness_notes.present?
  end

  test "qualify! marks rich ticket as bounty eligible" do
    ticket = create_rich_ticket

    result = TicketQualificationService.qualify!(ticket, auto_enrich: true)

    assert result[:eligible], "Rich ticket should be bounty eligible"
    assert ticket.bounty_eligible?
  end

  test "qualify! marks thin ticket as NOT bounty eligible" do
    ticket = SupportTicket.create!(
      entity: @entity,
      title: "error",
      description: "something wrong",
      source: 'user_reported',
      priority: 'medium',
      category: 'bug'
    )

    result = TicketQualificationService.qualify!(ticket, auto_enrich: true)

    assert_not result[:eligible], "Thin ticket should NOT be bounty eligible"
    assert_not ticket.bounty_eligible?
    assert ticket.bounty_blocked_reason.present?
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # COMPONENT INFERENCE
  # ═══════════════════════════════════════════════════════════════════════════

  test "infers API component from controller path" do
    result = TicketQualificationService.send(:infer_component_from_file, 'app/controllers/api/v1/contacts_controller.rb')
    assert_equal 'API', result
  end

  test "infers Scout component from scout controller" do
    result = TicketQualificationService.send(:infer_component_from_file, 'app/controllers/scout_controller.rb')
    assert_equal 'Scout/Chat', result
  end

  test "infers Tools component from tools service" do
    result = TicketQualificationService.send(:infer_component_from_file, 'app/services/tools/web_search_tool.rb')
    assert_equal 'Tools', result
  end

  test "infers AMOS Core from amos service" do
    result = TicketQualificationService.send(:infer_component_from_file, 'app/services/amos/orchestrator.rb')
    assert_equal 'AMOS Core', result
  end

  test "returns nil for unknown path" do
    result = TicketQualificationService.send(:infer_component_from_file, 'vendor/gems/something.rb')
    assert_nil result
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # READINESS LABELS
  # ═══════════════════════════════════════════════════════════════════════════

  test "readiness labels map correctly" do
    ticket = SupportTicket.new(entity: @entity)

    ticket.readiness_score = 0
    assert_equal 'Insufficient', ticket.readiness_label

    ticket.readiness_score = 45
    assert_equal 'Partial', ticket.readiness_label

    ticket.readiness_score = 65
    assert_equal 'Good', ticket.readiness_label

    ticket.readiness_score = 80
    assert_equal 'Strong', ticket.readiness_label

    ticket.readiness_score = 95
    assert_equal 'Excellent', ticket.readiness_label
  end

  private

  def create_rich_ticket
    SupportTicket.create!(
      entity: @entity,
      title: "Fix email notification delay on contact form submission page",
      description: "When a user submits the contact form on the landing page, they should receive a confirmation email within 5 minutes. Currently, no email is being sent. This was working last week before the Mailgun integration update.",
      source: 'user_reported',
      priority: 'high',
      category: 'bug',
      steps_to_reproduce: "1. Go to any landing page with a contact form\n2. Fill in name and email\n3. Click Submit\n4. Wait 10 minutes\n5. Check email — nothing received",
      expected_behavior: "User should receive a confirmation email within 5 minutes of form submission",
      actual_behavior: "No email is sent. No errors in the UI but server logs show a Mailgun timeout error.",
      acceptance_criteria: ["Email sends within 5 minutes of form submit", "Email contains the user's name", "Mailgun timeout errors are handled gracefully", "User sees a success message even if email is queued"],
      affected_component: "Email/Notifications",
      error_message: "Net::ReadTimeout: Mailgun API call timed out after 30s",
      suggested_approach: "Check the Mailgun integration configuration. The timeout may need to be increased or emails should be queued via background job.",
      estimated_effort: 'small'
    )
  end
end
