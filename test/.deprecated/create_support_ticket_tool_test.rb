# frozen_string_literal: true

require 'test_helper'

class CreateSupportTicketToolTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @tool = Tools::CreateSupportTicketTool.new(user: @user, entity: @entity)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # BASIC CREATION
  # ═══════════════════════════════════════════════════════════════════════════

  test "creates ticket with required fields only" do
    result = @tool.execute({
      'title' => 'Dashboard loading slowly',
      'description' => 'The dashboard takes over 10 seconds to load for all users'
    })

    assert result[:success], "Should create ticket: #{result[:error]}"
    assert result[:ticket_number].present?
    assert result[:ticket_number].start_with?('AMOS-')
  end

  test "creates ticket with all structured fields" do
    result = @tool.execute({
      'title' => 'Email notification not sent after contact form submission',
      'description' => 'Users submit the contact form but no confirmation email is sent',
      'category' => 'bug',
      'priority' => 'high',
      'steps_to_reproduce' => "1. Go to landing page\n2. Fill in form\n3. Click submit\n4. Check email",
      'expected_behavior' => 'Confirmation email arrives within 5 minutes',
      'actual_behavior' => 'No email received after 30 minutes',
      'acceptance_criteria' => ['Email sends within 5 minutes', 'Sender name is correct'],
      'affected_component' => 'Email/Notifications',
      'error_message' => 'Net::ReadTimeout',
      'suggested_approach' => 'Check Mailgun integration configuration'
    })

    assert result[:success]

    ticket = SupportTicket.find_by(ticket_number: result[:ticket_number])
    assert ticket.present?
    assert_equal 'high', ticket.priority
    assert_equal 'bug', ticket.category
    assert ticket.steps_to_reproduce.present?
    assert ticket.expected_behavior.present?
    assert ticket.actual_behavior.present?
    assert ticket.acceptance_criteria.is_a?(Array)
    assert ticket.acceptance_criteria.length >= 2
    assert_equal 'Email/Notifications', ticket.affected_component
  end

  test "creates feature request with user story" do
    result = @tool.execute({
      'title' => 'Add CSV export to contacts page',
      'description' => 'Users need to export their contacts to CSV for use in other tools',
      'category' => 'feature_request',
      'priority' => 'medium',
      'user_story' => 'As a marketing manager, I want to export contacts to CSV so I can import them into Mailchimp',
      'business_value' => 'Reduces manual data entry by 2 hours per week for power users',
      'acceptance_criteria' => ['CSV includes all contact fields', 'Download starts within 5 seconds', 'Max 10,000 contacts per export']
    })

    assert result[:success]

    ticket = SupportTicket.find_by(ticket_number: result[:ticket_number])
    assert_equal 'feature_request', ticket.category
    assert ticket.user_story.present?
    assert ticket.business_value.present?
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # READINESS SCORING
  # ═══════════════════════════════════════════════════════════════════════════

  test "rich ticket gets high readiness score" do
    result = @tool.execute({
      'title' => 'Fix email notification delay on contact form submission page',
      'description' => 'When a user submits the contact form on the landing page, they should receive a confirmation email within 5 minutes. Currently no email is sent.',
      'category' => 'bug',
      'priority' => 'high',
      'steps_to_reproduce' => "1. Go to any landing page\n2. Submit form\n3. Wait 10 minutes\n4. No email",
      'expected_behavior' => 'Email arrives within 5 minutes',
      'actual_behavior' => 'No email sent, Mailgun timeout in logs',
      'acceptance_criteria' => ['Email sends within 5 minutes', 'Error handled gracefully'],
      'affected_component' => 'Email/Notifications',
      'error_message' => 'Net::ReadTimeout: Mailgun API',
      'suggested_approach' => 'Increase timeout or queue emails via background job'
    })

    assert result[:success]
    assert result[:readiness_score] >= 60, "Rich ticket should have readiness >= 60, got #{result[:readiness_score]}"
    assert result[:bounty_eligible], "Rich ticket should be bounty eligible"
  end

  test "thin ticket gets low readiness score" do
    result = @tool.execute({
      'title' => 'bug',
      'description' => 'something broken'
    })

    assert result[:success]
    assert result[:readiness_score] < 50, "Thin ticket should have readiness < 50, got #{result[:readiness_score]}"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # DESCRIPTION BUILDING
  # ═══════════════════════════════════════════════════════════════════════════

  test "builds rich description with sections" do
    result = @tool.execute({
      'title' => 'Test ticket',
      'description' => 'Base description',
      'steps_to_reproduce' => '1. Do this\n2. Do that',
      'expected_behavior' => 'Should work',
      'actual_behavior' => 'Does not work',
      'error_message' => 'SomeError',
      'acceptance_criteria' => ['Fix the thing', 'Test the thing']
    })

    assert result[:success]
    ticket = SupportTicket.find_by(ticket_number: result[:ticket_number])

    assert ticket.description.include?('Base description')
    assert ticket.description.include?('Steps to Reproduce')
    assert ticket.description.include?('Expected Behavior')
    assert ticket.description.include?('Actual Behavior')
    assert ticket.description.include?('Error Message')
    assert ticket.description.include?('Acceptance Criteria')
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # VALIDATION
  # ═══════════════════════════════════════════════════════════════════════════

  test "fails without title" do
    result = @tool.execute({
      'description' => 'Missing title'
    })

    assert_not result[:success]
  end

  test "fails without description" do
    result = @tool.execute({
      'title' => 'Missing description'
    })

    assert_not result[:success]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # RESPONSE FORMAT
  # ═══════════════════════════════════════════════════════════════════════════

  test "response includes all expected fields" do
    result = @tool.execute({
      'title' => 'Test response fields',
      'description' => 'Testing the response format'
    })

    assert result[:success]
    assert result[:ticket_number].present?
    assert result[:status].present?
    assert result[:priority].present?
    assert result[:category].present?
    assert result.key?(:readiness_score)
    assert result.key?(:bounty_eligible)
    assert result[:message].present?
  end
end
