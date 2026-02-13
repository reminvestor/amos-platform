# frozen_string_literal: true

require 'test_helper'

class GuidanceLibraryEnrichedTest < ActiveSupport::TestCase
  # ═══════════════════════════════════════════════════════════════
  # INTEGRATION SETUP guidance (enriched with full flow)
  # ═══════════════════════════════════════════════════════════════

  test "integration_setup guidance includes full setup flow" do
    guidance = GuidanceLibrary.for_task(:integration_setup)
    assert_not_nil guidance

    assert_match /Setting Up NEW Integrations/i, guidance
    assert_match /web_search/i, guidance
    assert_match /platform_create.*integration/im, guidance
    assert_match /Integrations canvas/i, guidance
  end

  test "integration_setup guidance includes security warning" do
    guidance = GuidanceLibrary.for_task(:integration_setup)
    assert_match /NEVER ask for API keys/i, guidance
    assert_match /Integrations canvas UI/i, guidance
  end

  test "integration_setup guidance includes discover operations" do
    guidance = GuidanceLibrary.for_task(:integration_setup)
    assert_match /integration_actions/i, guidance
  end

  # ═══════════════════════════════════════════════════════════════
  # CUSTOM DOMAIN guidance (enriched with DNS flow)
  # ═══════════════════════════════════════════════════════════════

  test "custom_domain_management guidance includes full flow" do
    guidance = GuidanceLibrary.for_task(:custom_domain_management)
    assert_not_nil guidance

    assert_match /Register.*platform_create.*custom_domain/im, guidance
    assert_match /Verify Web DNS.*verify_domain/im, guidance
    assert_match /Verify Email.*verify_email_domain/im, guidance
    assert_match /Assign to assets.*assign_domain/im, guidance
    assert_match /platform_query.*custom_domains/im, guidance
  end

  test "custom_domain_management guidance includes DNS details" do
    guidance = GuidanceLibrary.for_task(:custom_domain_management)
    assert_match /CNAME/i, guidance
    assert_match /DKIM/i, guidance
    assert_match /SPF/i, guidance
    assert_match /DMARC/i, guidance
    assert_match /48 hours/i, guidance
  end

  test "custom_domain_management guidance mentions GoDaddy auto-config" do
    guidance = GuidanceLibrary.for_task(:custom_domain_management)
    assert_match /GoDaddy/i, guidance
  end

  # ═══════════════════════════════════════════════════════════════
  # APP DESIGN guidance (enriched with build details)
  # ═══════════════════════════════════════════════════════════════

  test "app_design guidance includes internal vs external" do
    guidance = GuidanceLibrary.for_task(:app_design)
    assert_not_nil guidance

    assert_match /Internal app/i, guidance
    assert_match /External-facing app/i, guidance
  end

  test "app_design guidance includes build details" do
    guidance = GuidanceLibrary.for_task(:app_design)
    assert_match /30-60s/i, guidance
    assert_match /database tables/i, guidance
    assert_match /CRUD/i, guidance
    assert_match /module_manager/i, guidance
  end

  test "app_design guidance includes using existing modules" do
    guidance = GuidanceLibrary.for_task(:app_design)
    assert_match /platform_query.*schema/im, guidance
    assert_match /platform_update.*app_module/im, guidance
    assert_match /Do NOT create new when user wants to modify/i, guidance
  end

  test "app_design guidance includes schema field types" do
    guidance = GuidanceLibrary.for_task(:app_design)
    assert_match /text.*textarea.*number/i, guidance
    assert_match /select.*boolean.*reference/i, guidance
  end

  # ═══════════════════════════════════════════════════════════════
  # LANDING PAGE CREATE guidance (enriched with when-to-use)
  # ═══════════════════════════════════════════════════════════════

  test "landing_page_create guidance includes when to use" do
    guidance = GuidanceLibrary.for_task(:landing_page_create)
    assert_not_nil guidance

    assert_match /Single marketing.*conversion page/i, guidance
    assert_match /DO NOT use landing_page for functional apps/i, guidance
  end

  test "landing_page_create guidance includes create call" do
    guidance = GuidanceLibrary.for_task(:landing_page_create)
    assert_match /platform_create.*landing_page/im, guidance
    assert_match /landing_page_editor/i, guidance
  end

  # ═══════════════════════════════════════════════════════════════
  # WEBSITE CREATE guidance (enriched)
  # ═══════════════════════════════════════════════════════════════

  test "website_create guidance includes when to use" do
    guidance = GuidanceLibrary.for_task(:website_create)
    assert_not_nil guidance

    assert_match /Multi-page sites/i, guidance
    assert_match /NOT for single marketing pages/i, guidance
  end

  test "website_create guidance includes page editor" do
    guidance = GuidanceLibrary.for_task(:website_create)
    assert_match /website_page_editor/i, guidance
  end

  test "website_create guidance includes page purpose" do
    guidance = GuidanceLibrary.for_task(:website_create)
    assert_match /page_purpose.*functional.*marketing/im, guidance
  end

  # ═══════════════════════════════════════════════════════════════
  # WEB APP CREATE guidance (enriched with decision shortcuts)
  # ═══════════════════════════════════════════════════════════════

  test "web_app_create guidance includes when to use" do
    guidance = GuidanceLibrary.for_task(:web_app_create)
    assert_not_nil guidance

    assert_match /External-facing functional applications/i, guidance
    assert_match /task trackers.*CRM portals.*customer dashboards/i, guidance
  end

  test "web_app_create guidance includes decision shortcuts" do
    guidance = GuidanceLibrary.for_task(:web_app_create)
    assert_match /task tracker app.*web_app/i, guidance
    assert_match /customer portal.*web_app/i, guidance
  end

  test "web_app_create guidance differentiates from other types" do
    guidance = GuidanceLibrary.for_task(:web_app_create)
    assert_match /NOT for marketing pages/i, guidance
  end

  # ═══════════════════════════════════════════════════════════════
  # EMAIL SEQUENCE guidance
  # ═══════════════════════════════════════════════════════════════

  test "email_sequence_create guidance distinguishes types" do
    guidance = GuidanceLibrary.for_task(:email_sequence_create)
    assert_not_nil guidance

    assert_match /Email Sequence.*Multi-step/i, guidance
    assert_match /Automation.*Single triggered/i, guidance
    assert_match /Campaign.*One-time blast/i, guidance
  end

  test "email_sequence_create guidance shows creation steps" do
    guidance = GuidanceLibrary.for_task(:email_sequence_create)
    assert_match /platform_create.*email_template/im, guidance
    assert_match /platform_create.*email_sequence/im, guidance
    assert_match /delay_days/i, guidance
  end

  test "email_sequence_create guidance warns against standalone automations" do
    guidance = GuidanceLibrary.for_task(:email_sequence_create)
    assert_match /ALWAYS use email_sequence.*NOT standalone automations/im, guidance
  end

  # ═══════════════════════════════════════════════════════════════
  # TASK TYPE DETECTION
  # ═══════════════════════════════════════════════════════════════

  test "detects web_app_create from customer portal message" do
    task = GuidanceLibrary.detect_task_type(message: "build a customer portal")
    assert_equal :web_app_create, task
  end

  test "detects web_app_create from task tracker app message" do
    task = GuidanceLibrary.detect_task_type(message: "build me a task tracker app")
    assert_equal :web_app_create, task
  end

  test "detects website_create from company site message" do
    task = GuidanceLibrary.detect_task_type(message: "build a website for my company")
    assert_equal :website_create, task
  end

  test "detects custom_domain_management from DNS message" do
    task = GuidanceLibrary.detect_task_type(message: "I need to set up a custom domain and configure DNS")
    assert_equal :custom_domain_management, task
  end

  test "detects email_sequence_create from drip message" do
    task = GuidanceLibrary.detect_task_type(message: "create an email drip sequence with 3 emails")
    assert_equal :email_sequence_create, task
  end

  test "detects email_sequence_create from day X message" do
    task = GuidanceLibrary.detect_task_type(message: "send emails on day 1, day 3, day 7")
    assert_equal :email_sequence_create, task
  end

  test "detects integration_setup from connect stripe message" do
    task = GuidanceLibrary.detect_task_type(message: "connect my Stripe account")
    assert_equal :integration_setup, task
  end

  test "detects app_design from module creation message" do
    task = GuidanceLibrary.detect_task_type(message: "create a new database module for inventory")
    assert_equal :app_design, task
  end
end
