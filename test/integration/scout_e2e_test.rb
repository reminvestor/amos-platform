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

    # Ensure entity_user exists
    EntityUser.find_or_create_by!(user: @user, entity: @entity) do |eu|
      eu.role = 'admin'
    end

    # Sign in
    sign_in_user(@user)
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

    assert result[:success], "Chat should succeed: #{result[:errors]&.join(', ')}"
    assert result[:tools_used].include?("platform_create"), "Should use platform_create, used: #{result[:tools_used]}"

    contact = Contact.find_by(entity: @entity, email: 'e2e.create@e2e-test.com')
    assert contact, "Contact should exist in database"
    assert_equal 'E2E', contact.first_name
    assert_equal 'active', contact.status
    assert_equal 'lead', contact.lifecycle_stage
  end

  test "e2e: create an email template through chat" do
    result = send_chat('Create an email template called "E2E Welcome" with subject "Hello!" and body "<p>Welcome!</p>"')

    assert result[:success], "Chat should succeed: #{result[:errors]&.join(', ')}"
    assert result[:tools_used].include?("platform_create"), "Should use platform_create"

    template = EmailTemplate.find_by(entity: @entity, name: 'E2E Welcome')
    assert template, "Template should exist in database"
    assert_equal 'Hello!', template.subject
  end

  test "e2e: query contacts returns data" do
    # Setup
    Contact.create!(entity: @entity, user: @user, first_name: 'Query', last_name: 'Test', email: 'query@e2e-test.com', status: 'active')

    result = send_chat("How many contacts do I have? Just reply with the number.")

    assert result[:success], "Chat should succeed"
    assert result[:tools_used].include?("platform_query"), "Should use platform_query"
    assert result[:response].present?, "Should have a response"
  end

  test "e2e: delete a contact through chat" do
    contact = Contact.create!(entity: @entity, user: @user, first_name: 'Delete', last_name: 'Test', email: 'delete@e2e-test.com', status: 'active')

    result = send_chat("Delete the contact with ID #{contact.id}")

    assert result[:success], "Chat should succeed"
    refute Contact.exists?(id: contact.id), "Contact should be deleted from database"
  end

  # ══════════════════════════════════════════════════════════════
  # TIER 2: Multi-step operations
  # ══════════════════════════════════════════════════════════════

  test "e2e: create automation rule" do
    # First create the template
    template = EmailTemplate.create!(entity: @entity, user: @user, name: 'E2E Auto Template', subject: 'Hi', body: '<p>Hello</p>')

    result = send_chat("Create an automation called 'E2E Welcome Auto' that sends email template #{template.id} when a new contact is created")

    assert result[:success], "Chat should succeed: #{result[:errors]&.join(', ')}"

    automation = AutomationCode.find_by(entity: @entity, name: 'E2E Welcome Auto')
    assert automation, "AutomationCode should exist in database"
    assert_equal 'record_created', automation.trigger_type
    assert_equal 'active', automation.status
  end

  test "e2e: add custom field to contacts" do
    result = send_chat('Add a custom field called "e2e_test_field" of type "string" to contacts')

    assert result[:success], "Chat should succeed: #{result[:errors]&.join(', ')}"

    field_def = CustomFieldDefinition.find_by(entity: @entity, model_type: 'Contact', field_name: 'e2e_test_field')
    assert field_def, "CustomFieldDefinition should exist"
    assert_equal 'string', field_def.field_type
    assert field_def.active?
  end

  # ══════════════════════════════════════════════════════════════
  # TIER 3: Context and canvas
  # ══════════════════════════════════════════════════════════════

  test "e2e: canvas context is passed to agent" do
    page = LandingPage.create!(entity: @entity, user: @user, title: 'E2E Context Test', slug: 'e2e-context-test', status: 'draft', html_content: '<h1>Test</h1>')

    result = send_chat(
      "What landing page am I looking at?",
      canvas: { type: "landing_page_editor", data: { landing_page_id: page.id } }
    )

    assert result[:success], "Chat should succeed"
    # The response should reference the landing page or its ID
    assert(
      result[:response]&.include?(page.title) || result[:response]&.include?(page.id.to_s),
      "Response should reference the landing page. Got: #{result[:response]&.truncate(200)}"
    )

    page.destroy
  end

  private

  # ══════════════════════════════════════════════════════════════
  # HELPERS
  # ══════════════════════════════════════════════════════════════

  def sign_in_user(user)
    post user_session_path, params: {
      user: { email: user.email, password: 'password' }
    }
    follow_redirect! if response.redirect?
  end

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
