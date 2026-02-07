# frozen_string_literal: true

require "test_helper"

class AutomationActionRegistryTest < ActiveSupport::TestCase
  # ══════════════════════════════════════════════════════════════
  # AVAILABLE ACTIONS
  # ══════════════════════════════════════════════════════════════

  test "lists all available actions" do
    actions = AutomationActionRegistry.available_actions
    assert actions.is_a?(Array)
    assert actions.length >= 6

    action_names = actions.map { |a| a[:action] }
    %w[send_email add_to_campaign update_field create_activity call_webhook notify_user].each do |name|
      assert action_names.include?(name), "Should include action: #{name}"
    end
  end

  test "each action has description and required_config" do
    AutomationActionRegistry.available_actions.each do |action|
      assert action[:description].present?, "#{action[:action]} should have description"
      assert action[:required_config].is_a?(Array), "#{action[:action]} should have required_config array"
    end
  end

  # ══════════════════════════════════════════════════════════════
  # CODE GENERATION
  # ══════════════════════════════════════════════════════════════

  test "generates send_email code" do
    code = AutomationActionRegistry.generate_code(
      action: "send_email",
      action_config: { "template_id" => 42 },
      trigger: "record_created",
      name: "Test Email"
    )

    assert code.present?
    assert code.include?("def execute(trigger_data)")
    assert code.include?("WorkflowMailer")
    assert code.include?("42")  # template_id baked in
    assert_not code.include?("require")  # No requires (blocked by sandbox)
  end

  test "generates add_to_campaign code" do
    code = AutomationActionRegistry.generate_code(
      action: "add_to_campaign",
      action_config: { "campaign_id" => 7 },
      trigger: "record_created",
      name: "Test Campaign"
    )

    assert code.present?
    assert code.include?("def execute(trigger_data)")
    assert code.include?("7")  # campaign_id
  end

  test "generates update_field code" do
    code = AutomationActionRegistry.generate_code(
      action: "update_field",
      action_config: { "field" => "lifecycle_stage", "value" => "customer" },
      trigger: "record_created",
      name: "Test Update"
    )

    assert code.present?
    assert code.include?("lifecycle_stage")
    assert code.include?("customer")
  end

  test "generates create_activity code" do
    code = AutomationActionRegistry.generate_code(
      action: "create_activity",
      action_config: { "activity_type" => "note", "subject" => "Auto note" },
      trigger: "record_created",
      name: "Test Activity"
    )

    assert code.present?
    assert code.include?("Activity.create!")
    assert code.include?("note")
  end

  test "generates call_webhook code" do
    code = AutomationActionRegistry.generate_code(
      action: "call_webhook",
      action_config: { "url" => "https://example.com/hook" },
      trigger: "record_created",
      name: "Test Webhook"
    )

    assert code.present?
    assert code.include?("http_post")  # Uses sandbox helper, not Net::HTTP
    assert code.include?("example.com/hook")
    assert_not code.include?("Net::HTTP")  # Blocked by sandbox
    assert_not code.include?("require")    # Blocked by sandbox
  end

  test "generates notify_user code" do
    code = AutomationActionRegistry.generate_code(
      action: "notify_user",
      action_config: { "message" => "New contact added" },
      trigger: "record_created",
      name: "Test Notify"
    )

    assert code.present?
    assert code.include?("AgentWorkItem.create!")
    assert code.include?("New contact added")
  end

  # ══════════════════════════════════════════════════════════════
  # ERROR HANDLING
  # ══════════════════════════════════════════════════════════════

  test "raises error for unknown action" do
    assert_raises(ArgumentError) do
      AutomationActionRegistry.generate_code(
        action: "fly_to_moon",
        action_config: {},
        trigger: "record_created",
        name: "Bad"
      )
    end
  end

  test "raises error for missing required config" do
    assert_raises(ArgumentError) do
      AutomationActionRegistry.generate_code(
        action: "send_email",
        action_config: {},  # Missing template_id
        trigger: "record_created",
        name: "Bad"
      )
    end
  end

  # ══════════════════════════════════════════════════════════════
  # SANDBOX SAFETY
  # ══════════════════════════════════════════════════════════════

  test "generated code defines execute method" do
    AutomationActionRegistry::ACTIONS.each do |action_name, config|
      # Build minimal valid config
      action_config = {}
      config[:required_config].each { |k| action_config[k] = "test_value" }

      code = AutomationActionRegistry.generate_code(
        action: action_name,
        action_config: action_config,
        trigger: "record_created",
        name: "Safety Test"
      )

      assert code.include?("def execute(trigger_data)"),
        "#{action_name} code must define execute(trigger_data) method"
    end
  end

  test "no generated code uses blocked patterns" do
    blocked = [/\brequire\b/, /\bNet::HTTP\b/, /\bFile\b/, /\bIO\b/, /\bsystem\b/, /\beval\b/]

    AutomationActionRegistry::ACTIONS.each do |action_name, config|
      action_config = {}
      config[:required_config].each { |k| action_config[k] = "test_value" }

      code = AutomationActionRegistry.generate_code(
        action: action_name,
        action_config: action_config,
        trigger: "record_created",
        name: "Safety Test"
      )

      blocked.each do |pattern|
        assert_not code.match?(pattern),
          "#{action_name} code should not contain #{pattern.source}"
      end
    end
  end
end
