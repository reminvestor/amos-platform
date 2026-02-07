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

    sign_in @user
  end

  teardown do
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

  # Send a chat message via HTTP and parse the SSE response
  def send_chat(message, canvas: nil, timeout: 60)
    canvas ||= { type: "default", data: {}, title: "Default" }

    response_text = ""
    tools_used = []
    canvas_loaded = nil
    errors = []
    success = false

    begin
      post "/scout/chat_stream",
        params: { message: message, current_canvas: canvas, file_urls: [], model: nil },
        headers: { "Accept" => "text/event-stream", "Content-Type" => "application/json" },
        as: :json

      # Parse SSE response
      body = response.body.to_s
      
      body.split("\n").each do |line|
        next unless line.start_with?("data: ")
        
        json_str = line.sub("data: ", "").strip
        next if json_str.blank? || json_str == "[DONE]"

        begin
          chunk = JSON.parse(json_str)
          type = chunk["type"].to_s

          case type
          when "content"
            response_text += (chunk["content"] || "")
          when "tool_start"
            tools_used << chunk["name"] if chunk["name"]
          when "tool_complete"
            tools_used << chunk["name"] if chunk["name"] && !tools_used.include?(chunk["name"])
          when "load_canvas"
            canvas_loaded = chunk["canvas"]
          when "final"
            response_text = chunk["message"] if chunk["message"].present? && response_text.blank?
            if chunk["tools_used"].is_a?(Array)
              tools_used = (tools_used + chunk["tools_used"]).uniq
            end
          when "error"
            errors << (chunk["message"] || chunk["error"])
          end
        rescue JSON::ParserError
          # Skip malformed chunks
        end
      end

      success = response.status == 200 && errors.empty?
    rescue => e
      errors << e.message
    end

    {
      success: success,
      response: response_text,
      tools_used: tools_used.uniq,
      canvas_loaded: canvas_loaded,
      errors: errors,
      http_status: response&.status
    }
  end
end
