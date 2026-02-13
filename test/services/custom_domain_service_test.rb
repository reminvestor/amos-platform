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

  # ============================================
  # AUTO DNS CONFIGURATION (Fixed service ref)
  # ============================================

  test "auto_configure_dns returns error without GoDaddy connection" do
    custom_domain = CustomDomain.create!(entity: @entity, user: @user, domain_name: 'nogateway.com')
    service = CustomDomainService.new(custom_domain: custom_domain)

    result = service.auto_configure_dns

    assert_not result[:success]
    assert_includes result[:error], 'No GoDaddy connection'
  end

  test "auto_configure_dns uses IntegrationApiService when connection exists" do
    # Set up GoDaddy integration + connection + credential
    godaddy = Integration.create!(
      name: 'GoDaddy', slug: 'godaddy_dns_test', category: 'custom',
      auth_type: 'api_key', api_base_url: 'https://api.godaddy.com',
      is_active: true, is_verified: true
    )
    godaddy.integration_operations.create!(
      operation_id: 'godaddy.add_dns_record',
      name: 'Add DNS Record',
      http_method: 'PATCH',
      path_template: '/v1/domains/{domain}/records',
      is_idempotent: false
    )
    connection = Connection.create!(
      entity: @entity, integration: godaddy, user: @user,
      name: 'GoDaddy', status: :connected
    )
    IntegrationCredential.create!(
      connection: connection, name: 'GoDaddy Key',
      auth_method: 'header', status: :active,
      credentials: { 'api_key' => 'testkey', 'api_secret' => 'testsecret' }
    )
    custom_domain = CustomDomain.create!(
      entity: @entity, user: @user, domain_name: 'autodns-test.com',
      connection: connection
    )

    service = CustomDomainService.new(custom_domain: custom_domain)

    # Stub IntegrationApiService to avoid real HTTP call
    mock_response = stub(success?: true, code: 200, body: '{}')
    IntegrationApiService.any_instance.stubs(:execute_operation).returns(mock_response)

    result = service.auto_configure_dns

    assert result[:success]
    assert_includes result[:message], 'configured automatically'
    assert custom_domain.reload.auto_dns_configured?
  end

  test "auto_configure_dns handles API errors gracefully" do
    godaddy = Integration.create!(
      name: 'GoDaddy', slug: 'godaddy_err_test', category: 'custom',
      auth_type: 'api_key', api_base_url: 'https://api.godaddy.com',
      is_active: true, is_verified: true
    )
    godaddy.integration_operations.create!(
      operation_id: 'godaddy.add_dns_record',
      name: 'Add DNS Record',
      http_method: 'PATCH',
      path_template: '/v1/domains/{domain}/records',
      is_idempotent: false
    )
    connection = Connection.create!(
      entity: @entity, integration: godaddy, user: @user,
      name: 'GoDaddy', status: :connected
    )
    IntegrationCredential.create!(
      connection: connection, name: 'GoDaddy Key',
      auth_method: 'header', status: :active,
      credentials: { 'api_key' => 'testkey', 'api_secret' => 'testsecret' }
    )
    custom_domain = CustomDomain.create!(
      entity: @entity, user: @user, domain_name: 'apierr.com',
      connection: connection
    )

    service = CustomDomainService.new(custom_domain: custom_domain)

    # Stub a failed response
    mock_response = stub(success?: false, code: 422, body: 'Invalid records')
    IntegrationApiService.any_instance.stubs(:execute_operation).returns(mock_response)

    result = service.auto_configure_dns

    assert_not result[:success]
    assert_includes result[:error], 'GoDaddy API error'
  end
end
