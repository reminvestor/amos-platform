# frozen_string_literal: true

require "test_helper"

class V3::Tools::PlatformCreateToolTest < ActiveSupport::TestCase
  fixtures :users, :entities

  setup do
    @user = users(:one)
    @entity = entities(:one)
    @tool = V3::Tools::PlatformCreateTool.new(user: @user, entity: @entity)
  end

  # ══════════════════════════════════════════════════════════════
  # METADATA
  # ══════════════════════════════════════════════════════════════

  test "metadata has correct name and category" do
    metadata = V3::Tools::PlatformCreateTool.metadata
    assert_equal "platform_create", metadata[:name]
    assert_equal "v3_core", metadata[:category]
    assert metadata[:description].present?
  end

  test "metadata lists supported types" do
    desc = V3::Tools::PlatformCreateTool.metadata[:description]
    %w[contact email_template campaign automation landing_page app sync].each do |type|
      assert desc.include?(type), "Description should mention #{type}"
    end
  end

  # ══════════════════════════════════════════════════════════════
  # VALIDATION
  # ══════════════════════════════════════════════════════════════

  test "returns error for missing type" do
    result = @tool.execute({ "data" => { "name" => "test" } })
    assert_equal false, result[:success]
    assert_match(/type/i, result[:error])
  end

  test "returns error for missing data" do
    result = @tool.execute({ "type" => "contact" })
    assert_equal false, result[:success]
    assert_match(/data/i, result[:error])
  end

  # ══════════════════════════════════════════════════════════════
  # CONTACT CREATION
  # ══════════════════════════════════════════════════════════════

  test "creates contact with correct defaults" do
    result = @tool.execute({
      "type" => "contact",
      "data" => { "first_name" => "Test", "last_name" => "User", "email" => "create-test@tool-test.com" }
    })

    assert result[:success] != false, "Should succeed: #{result[:error]}"

    contact = Contact.find_by(email: "create-test@tool-test.com")
    assert contact, "Contact should be created"
    assert_equal "active", contact.status
    assert_equal "lead", contact.lifecycle_stage
  ensure
    Contact.where(email: "create-test@tool-test.com").destroy_all
  end

  # ══════════════════════════════════════════════════════════════
  # EMAIL TEMPLATE CREATION
  # ══════════════════════════════════════════════════════════════

  test "creates email template" do
    result = @tool.execute({
      "type" => "email_template",
      "data" => { "name" => "Tool Test Template", "subject" => "Hello", "body" => "<p>Hi</p>" }
    })

    assert result[:success] != false, "Should succeed: #{result[:error]}"

    template = EmailTemplate.find_by(entity: @entity, name: "Tool Test Template")
    assert template, "Template should be created"
    assert_equal "Hello", template.subject
  ensure
    EmailTemplate.where(entity: @entity, name: "Tool Test Template").destroy_all
  end

  # ══════════════════════════════════════════════════════════════
  # AUTOMATION CREATION
  # ══════════════════════════════════════════════════════════════

  test "creates automation with action template" do
    # First create a template to reference
    template = EmailTemplate.create!(entity: @entity, user: @user, name: "Auto Test Tmpl", subject: "Hi", body: "<p>Hello</p>")

    result = @tool.execute({
      "type" => "automation",
      "data" => {
        "name" => "Tool Test Automation",
        "trigger" => "contact_created",
        "action" => "send_email",
        "action_config" => { "template_id" => template.id }
      }
    })

    assert result[:success] != false, "Should succeed: #{result[:error]}"
    assert result[:automation_id].present?, "Should return automation_id"

    automation = AutomationCode.find_by(id: result[:automation_id])
    assert automation, "AutomationCode should exist"
    assert_equal "record_created", automation.trigger_type
    assert_equal "active", automation.status
    assert automation.code.present?, "Should have generated code"
  ensure
    AutomationCode.where(entity: @entity, name: "Tool Test Automation").destroy_all
    template&.destroy
  end

  test "returns error for automation with unknown action" do
    result = @tool.execute({
      "type" => "automation",
      "data" => {
        "name" => "Bad Auto",
        "trigger" => "contact_created",
        "action" => "fly_to_moon",
        "action_config" => {}
      }
    })

    assert_equal false, result[:success]
    assert_match(/Unknown action/i, result[:error])
  end

  # ══════════════════════════════════════════════════════════════
  # BUILDER TYPES ROUTING
  # ══════════════════════════════════════════════════════════════

  test "routes landing_page to builder" do
    assert V3::Tools::PlatformCreateTool::BUILDER_TYPES.include?("landing_page")
  end

  test "routes automation to builder" do
    assert V3::Tools::PlatformCreateTool::BUILDER_TYPES.include?("automation")
  end

  test "routes sync to builder" do
    assert V3::Tools::PlatformCreateTool::BUILDER_TYPES.include?("sync")
  end

  test "routes app to builder" do
    assert V3::Tools::PlatformCreateTool::BUILDER_TYPES.include?("app")
  end

  test "routes scheduled_task to builder" do
    assert V3::Tools::PlatformCreateTool::BUILDER_TYPES.include?("scheduled_task")
  end

  # ══════════════════════════════════════════════════════════════
  # SCHEDULED TASK CREATION
  # ══════════════════════════════════════════════════════════════

  test "creates scheduled task" do
    result = @tool.execute({
      "type" => "scheduled_task",
      "data" => { "name" => "E2E Test Task", "prompt" => "Generate a weekly report", "schedule" => "weekly" }
    })

    assert result[:success] != false, "Should succeed: #{result[:error]}"
    assert result[:task_id].present?

    task = ScheduledAgentTask.find_by(id: result[:task_id])
    assert task, "Task should exist"
    assert_equal "E2E Test Task", task.name
    assert_equal "active", task.status
  ensure
    ScheduledAgentTask.where(entity: @entity, name: "E2E Test Task").destroy_all
  end

  test "scheduled task requires name and prompt" do
    result = @tool.execute({
      "type" => "scheduled_task",
      "data" => { "schedule" => "daily" }
    })
    assert_equal false, result[:success]
    assert_match /name/i, result[:error]
  end
end
