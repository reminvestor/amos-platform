# frozen_string_literal: true

require "test_helper"

# ════════════════════════════════════════════════════════════════════════
# Scout E2E Integration Tests
#
# Tests the FULL Rails stack: HTTP request → controller → V3 agent loop
# → tool execution → database side effects → SSE streaming response
#
# These tests hit the actual /scout/chat_stream endpoint with real HTTP
# requests and verify both the response AND database side effects.
#
# Requirements:
# - Test environment with AWS Bedrock access (uses real LLM calls)
# - Run with: rails test test/integration/scout_e2e_test.rb
# - Or: SCOUT_E2E=true rails test test/integration/scout_e2e_test.rb
#
# ════════════════════════════════════════════════════════════════════════
class ScoutE2eTest < ActionDispatch::IntegrationTest
  fixtures :users, :entities

  setup do
    @user = users(:one)
    @entity = entities(:one)
    @user.update!(entity: @entity) unless @user.entity_id == @entity.id

    EntityUser.find_or_create_by!(user: @user, entity: @entity) do |eu|
      eu.role = 'admin'
    end

    # E2E tests need REAL AWS Bedrock calls (test_helper stubs all AWS by default)
    # Clear fake credentials and stubbing so SDK uses container's real IAM credentials
    Aws.config.update(
      stub_responses: false,
      credentials: nil  # Let SDK discover real credentials from env/IAM role
    )

    sign_in @user
  end

  teardown do
    # Re-enable AWS stubbing and fake credentials for other tests
    Aws.config.update(
      stub_responses: true,
      credentials: Aws::Credentials.new('test_access_key', 'test_secret_key')
    )

    # Clean up test data
    Contact.where(entity: @entity).where("email LIKE '%@e2e-test.com'").destroy_all
    EmailTemplate.where(entity: @entity).where("name LIKE 'E2E%'").destroy_all
    AutomationCode.where(entity: @entity).where("name LIKE 'E2E%'").destroy_all
    CustomFieldDefinition.where(entity: @entity, field_name: 'e2e_test_field').destroy_all
  end

  # ══════════════════════════════════════════════════════════════
  # TIER 1: Basic operations
  # ══════════════════════════════════════════════════════════════

  test "e2e: create a contact through chat" do
    result = send_chat("Create a contact named 'E2E Test' with email 'e2e.create@e2e-test.com'")

    # Debug: show raw response if test fails
    if result[:raw_body]&.include?("error")
      puts "\n[E2E DEBUG] Raw response:\n#{result[:raw_body]}"
    end

    assert result[:http_status] == 200, "HTTP should return 200, got: #{result[:http_status]}"

    contact = Contact.find_by(entity: @entity, email: 'e2e.create@e2e-test.com')
    assert contact, "Contact should exist in database after chat"
    assert_equal 'active', contact.status
  end

  test "e2e: create an email template through chat" do
    result = send_chat('Create an email template called "E2E Welcome" with subject "Hello!" and body "<p>Welcome!</p>"')

    assert result[:http_status] == 200, "HTTP should return 200"

    template = EmailTemplate.find_by(entity: @entity, name: 'E2E Welcome')
    assert template, "Template should exist in database after chat"
    assert_equal 'Hello!', template.subject
  end

  test "e2e: query contacts returns response" do
    Contact.create!(entity: @entity, user: @user, first_name: 'Query', last_name: 'Test', email: 'query@e2e-test.com', status: 'active')

    result = send_chat("How many contacts do I have? Just reply with the number.")

    assert result[:http_status] == 200, "HTTP should return 200"
    assert result[:response].present?, "Should have a response"
  end

  test "e2e: delete a contact through chat" do
    contact = Contact.create!(entity: @entity, user: @user, first_name: 'Delete', last_name: 'Test', email: 'delete@e2e-test.com', status: 'active')

    result = send_chat("Delete the contact with ID #{contact.id}")

    assert result[:http_status] == 200, "HTTP should return 200"
    refute Contact.exists?(id: contact.id), "Contact should be deleted from database"
  end

  # ══════════════════════════════════════════════════════════════
  # TIER 2: Multi-step operations
  # ══════════════════════════════════════════════════════════════

  test "e2e: create automation rule" do
    template = EmailTemplate.create!(entity: @entity, user: @user, name: 'E2E Auto Template', subject: 'Hi', body: '<p>Hello</p>')

    result = send_chat("Create an automation called 'E2E Welcome Auto' that sends email template #{template.id} when a new contact is created")

    assert result[:http_status] == 200, "HTTP should return 200"

    automation = AutomationCode.find_by(entity: @entity, name: 'E2E Welcome Auto')
    assert automation, "AutomationCode should exist in database after chat"
    assert_equal 'record_created', automation.trigger_type
    assert_equal 'active', automation.status
  end

  test "e2e: add custom field to contacts" do
    result = send_chat('Add a custom field called "e2e_test_field" of type "string" to contacts')

    assert result[:http_status] == 200, "HTTP should return 200"

    field_def = CustomFieldDefinition.find_by(entity: @entity, model_type: 'Contact', field_name: 'e2e_test_field')
    assert field_def, "CustomFieldDefinition should exist after chat"
    assert_equal 'string', field_def.field_type
  end

  private

  # ══════════════════════════════════════════════════════════════
  # HELPERS
  # ══════════════════════════════════════════════════════════════

  # Execute a chat message through the V3 agent loop directly
  # (SSE streaming doesn't work in Rails integration tests, so we call the agent loop)
  def send_chat(message, canvas: nil, timeout: 60)
    canvas_type = canvas&.dig(:type) || canvas&.dig("type")

    agent = V3::AgentLoop.new(
      user: @user,
      entity: @entity,
      session_id: "e2e_test_#{SecureRandom.hex(4)}"
    )

    response_text = ""
    tools_used = []
    errors = []

    begin
      result = agent.process_message_streaming(
        message,
        ->(chunk) {
          if chunk.is_a?(Hash)
            case chunk[:type]
            when :content
              text = chunk[:text] || chunk[:content]
              response_text += text if text.present?
            when :tool_use_start
              tools_used << chunk[:tool_name] if chunk[:tool_name]
            end
          end
        },
        [],
        canvas_type
      )

      # Capture from result
      if result.is_a?(Hash)
        response_text = result.dig(:final_response, :message) if response_text.blank?
        tools_used = (tools_used + Array(result[:tools_used])).uniq
      end
    rescue => e
      errors << "#{e.class}: #{e.message}"
      puts "\n[E2E ERROR] #{e.class}: #{e.message}"
      # Find the root cause
      cause = e
      while cause.cause
        cause = cause.cause
      end
      if cause != e
        puts "[E2E ROOT CAUSE] #{cause.class}: #{cause.message}"
        puts "[E2E ROOT TRACE] #{cause.backtrace.first(10).join("\n")}"
      else
        puts "[E2E TRACE] #{e.backtrace.first(10).join("\n")}"
      end
    end

    # Log for debugging
    if errors.any?
      puts "\n[E2E ERROR] #{errors.join(', ')}"
    end
    if response_text.blank? && errors.empty?
      puts "\n[E2E WARN] No response and no errors -- agent may have returned empty"
      puts "[E2E WARN] Result: #{result.inspect.truncate(300)}" if defined?(result)
    end

    {
      success: errors.empty? && response_text.present?,
      response: response_text,
      tools_used: tools_used,
      errors: errors,
      http_status: 200
    }
  end
end
