# frozen_string_literal: true

require "test_helper"

class WebsitePageGeneratorServiceTest < ActiveSupport::TestCase
  fixtures :users, :entities

  setup do
    @user = users(:one)
    @entity = entities(:one)
    @service = WebsitePageGeneratorService.new(user: @user, entity: @entity)
  end

  # ═══════════════════════════════════════════════════════════════
  # PURPOSE INFERENCE
  # ═══════════════════════════════════════════════════════════════

  test "infers functional purpose for dashboard template" do
    result = @service.send(:infer_purpose, "dashboard", "Dashboard", "Overview of metrics")
    assert_equal "functional", result
  end

  test "infers functional purpose for form template" do
    result = @service.send(:infer_purpose, "form", "Add Task", "Create a new task entry")
    assert_equal "functional", result
  end

  test "infers functional purpose for list template" do
    result = @service.send(:infer_purpose, "list", "Tasks", "Browse all tasks")
    assert_equal "functional", result
  end

  test "infers functional purpose for detail template" do
    result = @service.send(:infer_purpose, "detail", "Task Detail", "View task details")
    assert_equal "functional", result
  end

  test "infers functional purpose for settings template" do
    result = @service.send(:infer_purpose, "settings", "Settings", "Manage account settings")
    assert_equal "functional", result
  end

  test "infers functional purpose for calendar template" do
    result = @service.send(:infer_purpose, "calendar", "Calendar", "Schedule view")
    assert_equal "functional", result
  end

  test "infers functional purpose for kanban template" do
    result = @service.send(:infer_purpose, "kanban", "Board", "Task board view")
    assert_equal "functional", result
  end

  test "infers marketing purpose for homepage template" do
    result = @service.send(:infer_purpose, "homepage", "Home", "Welcome to our company")
    assert_equal "marketing", result
  end

  test "infers functional purpose from description keywords" do
    result = @service.send(:infer_purpose, "content", "My Page", "Admin panel for task management")
    assert_equal "functional", result
  end

  test "infers functional purpose from dashboard keyword in description" do
    result = @service.send(:infer_purpose, "content", "Analytics", "Analytics dashboard showing reports")
    assert_equal "functional", result
  end

  test "infers functional purpose from tracker keyword" do
    result = @service.send(:infer_purpose, "custom", "Task Tracker", "Track weekly tasks")
    assert_equal "functional", result
  end

  test "infers marketing purpose from landing keyword" do
    result = @service.send(:infer_purpose, "content", "Launch Page", "Product landing page with signup")
    assert_equal "marketing", result
  end

  test "infers marketing purpose from promotion keyword" do
    result = @service.send(:infer_purpose, "content", "Summer Sale", "Summer promotion campaign page")
    assert_equal "marketing", result
  end

  test "defaults content template to functional" do
    result = @service.send(:infer_purpose, "content", "Info", "General information page")
    assert_equal "functional", result
  end

  # ═══════════════════════════════════════════════════════════════
  # TEMPLATE INFERENCE
  # ═══════════════════════════════════════════════════════════════

  test "infers dashboard template from title" do
    result = @service.send(:infer_template, "Analytics Dashboard", "Overview of business metrics")
    assert_equal "dashboard", result
  end

  test "infers form template from title" do
    result = @service.send(:infer_template, "Create New Task", "Add a new task to the tracker")
    assert_equal "form", result
  end

  test "infers list template from title" do
    result = @service.send(:infer_template, "Task List", "Browse all tasks")
    assert_equal "list", result
  end

  test "infers kanban template from title" do
    result = @service.send(:infer_template, "Task Board", "Kanban view of tasks")
    assert_equal "kanban", result
  end

  test "infers calendar template from title" do
    result = @service.send(:infer_template, "Schedule Planner", "Calendar view of events")
    assert_equal "calendar", result
  end

  test "infers settings template from title" do
    result = @service.send(:infer_template, "Account Settings", "Manage your preferences")
    assert_equal "settings", result
  end

  test "infers homepage template from title" do
    result = @service.send(:infer_template, "Home", "Welcome to our site")
    assert_equal "homepage", result
  end

  test "infers detail template from title" do
    result = @service.send(:infer_template, "Product Detail", "View a single product page")
    assert_equal "detail", result
  end

  test "defaults to content template" do
    result = @service.send(:infer_template, "About Us", "Learn about our company")
    assert_equal "content", result
  end

  # ═══════════════════════════════════════════════════════════════
  # TEMPLATE GUIDELINES
  # ═══════════════════════════════════════════════════════════════

  test "dashboard guidelines include metrics and charts" do
    guidelines = @service.send(:template_guidelines, "dashboard")
    assert_match /metrics/i, guidelines
    assert_match /chart/i, guidelines
  end

  test "form guidelines include validation and buttons" do
    guidelines = @service.send(:template_guidelines, "form")
    assert_match /validation/i, guidelines
    assert_match /save|submit/i, guidelines
  end

  test "list guidelines include table and search" do
    guidelines = @service.send(:template_guidelines, "list")
    assert_match /table/i, guidelines
    assert_match /search/i, guidelines
  end

  test "kanban guidelines include columns and drag" do
    guidelines = @service.send(:template_guidelines, "kanban")
    assert_match /column/i, guidelines
    assert_match /drag/i, guidelines
  end

  test "calendar guidelines include views and events" do
    guidelines = @service.send(:template_guidelines, "calendar")
    assert_match /monthly|weekly|daily/i, guidelines
    assert_match /event/i, guidelines
  end

  # ═══════════════════════════════════════════════════════════════
  # GENERATE METHOD (with stubbed AI)
  # ═══════════════════════════════════════════════════════════════

  test "generate returns success hash for functional page" do
    # Stub the AI call to return sample HTML
    sample_html = "<!DOCTYPE html><html><head><title>Dashboard</title></head><body><h1>Dashboard</h1></body></html>"
    @service.stubs(:call_ai).returns(sample_html)

    result = @service.generate({
      title: "Dashboard",
      description: "Analytics dashboard",
      template: "dashboard",
      page_purpose: "functional"
    })

    assert result[:success]
    assert_equal "functional", result[:page_type]
    assert_equal "dashboard", result[:template]
    assert_includes result[:html_content], "<!DOCTYPE html>"
    assert_includes result[:html_content], "Dashboard"
  end

  test "generate returns success hash for marketing page" do
    sample_html = "<!DOCTYPE html><html><head><title>Home</title></head><body><h1>Welcome</h1></body></html>"
    @service.stubs(:call_ai).returns(sample_html)

    result = @service.generate({
      title: "Home",
      description: "Company homepage",
      template: "homepage",
      page_purpose: "marketing"
    })

    assert result[:success]
    assert_equal "marketing", result[:page_type]
    assert_includes result[:html_content], "<!DOCTYPE html>"
  end

  test "generate auto-detects functional purpose" do
    sample_html = "<!DOCTYPE html><html><head><title>Tasks</title></head><body><table></table></body></html>"
    @service.stubs(:call_ai).returns(sample_html)

    result = @service.generate({
      title: "Task Tracker Dashboard",
      description: "Track and manage weekly tasks"
    })

    assert result[:success]
    assert_equal "functional", result[:page_type]
    assert_equal "dashboard", result[:template]
  end

  test "generate auto-detects marketing purpose" do
    sample_html = "<!DOCTYPE html><html><head><title>Promo</title></head><body><h1>Sale!</h1></body></html>"
    @service.stubs(:call_ai).returns(sample_html)

    result = @service.generate({
      title: "Summer Promo Page",
      description: "Promotional landing page for summer sale campaign"
    })

    assert result[:success]
    assert_equal "marketing", result[:page_type]
  end

  test "generate handles errors gracefully" do
    @service.stubs(:call_ai).raises(StandardError.new("AI unavailable"))

    result = @service.generate({
      title: "Test Page",
      description: "A test page"
    })

    assert_equal false, result[:success]
    assert_match /AI unavailable/, result[:error]
  end

  test "generate accepts features array for functional pages" do
    sample_html = "<!DOCTYPE html><html><body>Features</body></html>"
    @service.stubs(:call_ai).returns(sample_html)

    result = @service.generate({
      title: "Task Manager",
      description: "Manage tasks",
      page_purpose: "functional",
      features: ["Add tasks", "Set priorities", "Track progress"]
    })

    assert result[:success]
  end

  test "generate accepts data_fields for functional pages" do
    sample_html = "<!DOCTYPE html><html><body>Fields</body></html>"
    @service.stubs(:call_ai).returns(sample_html)

    result = @service.generate({
      title: "Contact Form",
      description: "Contact submission form",
      template: "form",
      data_fields: ["name", "email", "phone", "message"]
    })

    assert result[:success]
    assert_equal "form", result[:template]
  end

  # ═══════════════════════════════════════════════════════════════
  # WEBSITE CONTEXT
  # ═══════════════════════════════════════════════════════════════

  test "initializes with website context" do
    website = Website.new(name: "Test Site", theme: "modern")
    service = WebsitePageGeneratorService.new(user: @user, entity: @entity, website: website)

    assert_not_nil service
  end

  # ═══════════════════════════════════════════════════════════════
  # CONSTANTS
  # ═══════════════════════════════════════════════════════════════

  test "FUNCTIONAL_TEMPLATES includes expected types" do
    %w[dashboard form list detail settings calendar kanban].each do |t|
      assert_includes WebsitePageGeneratorService::FUNCTIONAL_TEMPLATES, t
    end
  end

  test "MARKETING_TEMPLATES includes expected types" do
    %w[homepage landing].each do |t|
      assert_includes WebsitePageGeneratorService::MARKETING_TEMPLATES, t
    end
  end
end
