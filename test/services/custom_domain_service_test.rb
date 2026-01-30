# frozen_string_literal: true

require "test_helper"

class CustomDomainServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @service = CustomDomainService.new(entity: @entity, user: @user)
  end

  # ============================================
  # DOMAIN REGISTRATION
  # ============================================

  test "register_domain creates new custom domain" do
    result = @service.register_domain('newdomain.com')

    assert result[:success]
    assert result[:custom_domain].present?
    assert_equal 'newdomain.com', result[:custom_domain].domain_name
    assert result[:cname_target].present?
    assert result[:instructions].present?
  end

  test "register_domain with subdomain" do
    result = @service.register_domain('example.com', subdomain: 'app')

    assert result[:success]
    assert_equal 'app', result[:custom_domain].subdomain
    assert_equal 'app.example.com', result[:custom_domain].full_domain
  end

  test "register_domain fails for duplicate domain" do
    CustomDomain.create!(entity: @entity, user: @user, domain_name: 'duplicate.com')
    
    result = @service.register_domain('duplicate.com')

    assert_not result[:success]
    assert_equal "Domain duplicate.com is already registered", result[:error]
  end

  test "register_domain normalizes domain name" do
    result = @service.register_domain('HTTPS://Example.COM/')

    assert result[:success]
    assert_equal 'example.com', result[:custom_domain].domain_name
  end

  # ============================================
  # DNS VERIFICATION
  # ============================================

  test "verify_web_dns returns error without custom domain" do
    service = CustomDomainService.new(entity: @entity, user: @user)
    result = service.verify_web_dns

    assert_not result[:success]
    assert_equal 'No custom domain specified', result[:error]
  end

  test "dns_setup_instructions returns instructions" do
    custom_domain = CustomDomain.create!(
      entity: @entity,
      user: @user,
      domain_name: 'test.com'
    )
    
    service = CustomDomainService.new(custom_domain: custom_domain)
    instructions = service.send(:dns_setup_instructions, custom_domain)
    
    assert instructions.present?
    assert instructions.include?('CNAME') || instructions.include?(custom_domain.cname_target)
  end
end
