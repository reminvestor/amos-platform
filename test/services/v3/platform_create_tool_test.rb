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

  test "routes website to builder" do
    assert V3::Tools::PlatformCreateTool::BUILDER_TYPES.include?("website")
  end

  test "routes web_app to builder" do
    assert V3::Tools::PlatformCreateTool::BUILDER_TYPES.include?("web_app")
  end

  # ══════════════════════════════════════════════════════════════
  # WEBSITE CREATION
  # ══════════════════════════════════════════════════════════════

  test "website creation requires pages" do
    result = @tool.execute({
      "type" => "website",
      "data" => { "name" => "My Site" }
    })

    assert_equal false, result[:success]
    assert_match /page/i, result[:error]
  end

  test "website creation creates Website record" do
    # Stub the AI generation
    WebsitePageGeneratorService.any_instance.stubs(:call_ai).returns(
      "<!DOCTYPE html><html><head><title>Home</title></head><body><h1>Home</h1></body></html>"
    )

    result = @tool.execute({
      "type" => "website",
      "data" => {
        "name" => "Test Website",
        "pages" => [{ "title" => "Home", "description" => "Homepage" }]
      }
    })

    assert result[:success] != false, "Should succeed: #{result[:error]}"
    assert result[:website_id].present?

    website = Website.find_by(id: result[:website_id])
    assert website, "Website should exist"
    assert_equal "Test Website", website.name
    assert_equal "draft", website.status
  ensure
    Website.where(entity: @entity, name: "Test Website").destroy_all
  end

  test "website creation creates WebsitePage records" do
    WebsitePageGeneratorService.any_instance.stubs(:call_ai).returns(
      "<!DOCTYPE html><html><head><title>Page</title></head><body><h1>Page</h1></body></html>"
    )

    result = @tool.execute({
      "type" => "website",
      "data" => {
        "name" => "Multi Page Site",
        "pages" => [
          { "title" => "Home", "description" => "Homepage" },
          { "title" => "About", "description" => "About page" }
        ]
      }
    })

    assert result[:success] != false, "Should succeed: #{result[:error]}"
    assert_equal 2, result[:page_count]

    website = Website.find_by(id: result[:website_id])
    assert_equal 2, website.website_pages.count
    assert website.website_pages.find_by(name: "Home").is_homepage
  ensure
    Website.where(entity: @entity, name: "Multi Page Site").destroy_all
  end

  test "website uses WebsitePageGeneratorService not LandingPage" do
    WebsitePageGeneratorService.any_instance.stubs(:call_ai).returns(
      "<!DOCTYPE html><html><body>Functional page</body></html>"
    )

    initial_lp_count = LandingPage.where(entity: @entity).count

    result = @tool.execute({
      "type" => "website",
      "data" => {
        "name" => "Func Site",
        "pages" => [{ "title" => "Dashboard", "description" => "App dashboard" }]
      }
    })

    assert result[:success] != false, "Should succeed: #{result[:error]}"
    # Should NOT create LandingPage records (old behavior)
    assert_equal initial_lp_count, LandingPage.where(entity: @entity).count
  ensure
    Website.where(entity: @entity, name: "Func Site").destroy_all
  end

  # ══════════════════════════════════════════════════════════════
  # WEB APP CREATION
  # ══════════════════════════════════════════════════════════════

  test "web app creation creates WebApp record" do
    WebsitePageGeneratorService.any_instance.stubs(:call_ai).returns(
      "<!DOCTYPE html><html><body>App page</body></html>"
    )

    result = @tool.execute({
      "type" => "web_app",
      "data" => {
        "name" => "Task Tracker",
        "pages" => [{ "title" => "Dashboard", "description" => "Task dashboard" }]
      }
    })

    assert result[:success] != false, "Should succeed: #{result[:error]}"
    assert result[:web_app_id].present?, "Should return web_app_id"

    web_app = WebApp.find_by(id: result[:web_app_id])
    assert web_app, "WebApp should exist"
    assert_equal "Task Tracker", web_app.name
    assert_equal "draft", web_app.status
    assert web_app.subdomain.present?, "Should have a subdomain"
  ensure
    WebApp.where(entity: @entity, name: "Task Tracker").delete_all
    Website.where(entity: @entity, name: "Task Tracker").destroy_all
  end

  test "web app creation links to website" do
    WebsitePageGeneratorService.any_instance.stubs(:call_ai).returns(
      "<!DOCTYPE html><html><body>Page</body></html>"
    )

    result = @tool.execute({
      "type" => "web_app",
      "data" => {
        "name" => "My Portal",
        "pages" => [{ "title" => "Home", "description" => "Portal home" }]
      }
    })

    assert result[:success] != false
    web_app = WebApp.find_by(id: result[:web_app_id])
    assert web_app.website_id.present?, "WebApp should be linked to a Website"
    assert_equal result[:website_id], web_app.website_id
  ensure
    WebApp.where(entity: @entity, name: "My Portal").delete_all
    Website.where(entity: @entity, name: "My Portal").destroy_all
  end

  test "web app creation without pages still creates WebApp" do
    result = @tool.execute({
      "type" => "web_app",
      "data" => {
        "name" => "API Only App",
        "description" => "Backend-only web app"
      }
    })

    assert result[:success] != false, "Should succeed: #{result[:error]}"
    assert result[:web_app_id].present?

    web_app = WebApp.find_by(id: result[:web_app_id])
    assert web_app, "WebApp should exist even without pages"
    assert_nil web_app.website_id, "Should have no website when no pages provided"
  ensure
    WebApp.where(entity: @entity, name: "API Only App").delete_all
  end

  test "web app creation links modules" do
    WebsitePageGeneratorService.any_instance.stubs(:call_ai).returns(
      "<!DOCTYPE html><html><body>Page</body></html>"
    )

    # Create an app module to link
    app_mod = AppModule.create!(
      entity: @entity,
      name: "Tasks Module",
      slug: "tasks_module_test",
      status: "active"
    )

    result = @tool.execute({
      "type" => "web_app",
      "data" => {
        "name" => "Linked App",
        "pages" => [{ "title" => "Home", "description" => "Home" }],
        "modules" => ["tasks_module_test"]
      }
    })

    assert result[:success] != false, "Should succeed: #{result[:error]}"
    assert_equal 1, result[:module_count]
    assert_includes result[:linked_modules], "Tasks Module"

    web_app = WebApp.find_by(id: result[:web_app_id])
    assert_equal 1, web_app.web_app_modules.count
    assert_equal app_mod.id, web_app.web_app_modules.first.app_module_id
  ensure
    if (wa = WebApp.find_by(entity: @entity, name: "Linked App"))
      WebAppModule.where(web_app_id: wa.id).delete_all
      wa.delete
    end
    Website.where(entity: @entity, name: "Linked App").destroy_all
    app_mod&.destroy
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
