# frozen_string_literal: true

require "test_helper"

class ManageCustomDomainToolTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @tool = Tools::ManageCustomDomainTool.new(user: @user, entity: @entity, context: {})
  end

  # ============================================
  # setup_web
  # ============================================

  test "setup_web creates a new custom domain" do
    result = @tool.execute({ action: "setup_web", domain_name: "newdomain.com" })

    assert result[:success]
    assert result[:domain_id].present?
    assert_equal "newdomain.com", result[:domain_name]
    assert result[:cname_target].present?
    assert_includes result[:message], "newdomain.com"
  end

  test "setup_web with subdomain" do
    result = @tool.execute({ action: "setup_web", domain_name: "mysite.com", subdomain: "app" })

    assert result[:success]
    assert_equal "app.mysite.com", result[:domain_name]
  end

  test "setup_web returns existing domain if already registered" do
    domain = CustomDomain.create!(entity: @entity, user: @user, domain_name: "existing.com")

    result = @tool.execute({ action: "setup_web", domain_name: "existing.com" })

    assert result[:success]
    assert result[:already_existed]
    assert_equal domain.id, result[:domain_id]
  end

  test "setup_web requires domain_name" do
    result = @tool.execute({ action: "setup_web" })

    assert_not result[:success]
    assert_includes result[:error], "domain_name"
  end

  test "setup_web includes manual instructions when no GoDaddy connection" do
    result = @tool.execute({ action: "setup_web", domain_name: "manual.com" })

    assert result[:success]
    assert_not result[:auto_dns]
    assert result[:dns_instructions].present?
  end

  test "setup_web detects GoDaddy connection for auto DNS" do
    godaddy = Integration.create!(
      name: 'GoDaddy', slug: 'godaddy', category: 'custom',
      auth_type: 'api_key', api_base_url: 'https://api.godaddy.com',
      is_active: true, is_verified: true
    )
    connection = Connection.create!(
      entity: @entity, integration: godaddy, user: @user,
      name: 'GoDaddy', status: :connected
    )

    # Stub the auto DNS scheduling to avoid actual job enqueue
    CustomDomainService.any_instance.stubs(:schedule_auto_dns_configuration).returns(nil)

    result = @tool.execute({ action: "setup_web", domain_name: "autodns.com" })

    assert result[:success], "Expected success but got: #{result[:error]}"
    assert result[:auto_dns], "Expected auto_dns to be true"
    assert_includes result[:message], "GoDaddy"
  end

  # ============================================
  # setup_email
  # ============================================

  test "setup_email starts SES verification" do
    domain = CustomDomain.create!(entity: @entity, user: @user, domain_name: "emailtest.com")

    SesDomainService.any_instance.stubs(:start_verification).returns({
      success: true,
      dns_records: { dkim: [], spf: { value: "v=spf1 include:amazonses.com ~all" } },
      instructions: "Add DNS records..."
    })

    result = @tool.execute({ action: "setup_email", domain_id: domain.id })

    assert result[:success]
    assert_equal domain.id, result[:domain_id]
  end

  test "setup_email requires existing domain" do
    result = @tool.execute({ action: "setup_email", domain_id: 99999 })

    assert_not result[:success]
    assert_includes result[:error], "not found"
  end

  test "setup_email returns early if already verified" do
    domain = CustomDomain.create!(
      entity: @entity, user: @user, domain_name: "verified-email.com",
      email_status: "verified", email_verified_at: Time.current
    )

    result = @tool.execute({ action: "setup_email", domain_id: domain.id })

    assert result[:success]
    assert_equal "verified", result[:email_status]
    assert_includes result[:message], "already verified"
  end

  # ============================================
  # check_status
  # ============================================

  test "check_status returns full domain status" do
    domain = CustomDomain.create!(
      entity: @entity, user: @user, domain_name: "status.com",
      web_status: "verified", web_verified_at: Time.current,
      ssl_status: "active", ssl_provisioned_at: Time.current,
      email_status: "pending"
    )

    result = @tool.execute({ action: "check_status", domain_id: domain.id })

    assert result[:success]
    assert_equal "verified", result[:web_status]
    assert_equal "active", result[:ssl_status]
    assert_equal "pending", result[:email_status]
    assert result[:fully_configured]
  end

  test "check_status finds by domain_name" do
    domain = CustomDomain.create!(entity: @entity, user: @user, domain_name: "byname.com")

    result = @tool.execute({ action: "check_status", domain_name: "byname.com" })

    assert result[:success]
    assert_equal domain.id, result[:domain_id]
  end

  test "check_status returns error for unknown domain" do
    result = @tool.execute({ action: "check_status", domain_id: 99999 })

    assert_not result[:success]
    assert_includes result[:error], "not found"
  end

  # ============================================
  # list
  # ============================================

  test "list returns all entity domains" do
    existing_count = CustomDomain.where(entity: @entity).count
    CustomDomain.create!(entity: @entity, user: @user, domain_name: "list1.com")
    CustomDomain.create!(entity: @entity, user: @user, domain_name: "list2.com")

    result = @tool.execute({ action: "list" })

    assert result[:success]
    assert_equal existing_count + 2, result[:count]
    assert_equal existing_count + 2, result[:domains].length
  end

  test "list returns empty message when no domains" do
    CustomDomain.where(entity: @entity).delete_all

    result = @tool.execute({ action: "list" })

    assert result[:success]
    assert_equal 0, result[:count]
    assert_includes result[:message], "No custom domains"
  end

  # ============================================
  # unknown action
  # ============================================

  test "returns error for unknown action" do
    result = @tool.execute({ action: "invalid" })

    assert_not result[:success]
    assert_includes result[:error], "Unknown action"
  end
end
