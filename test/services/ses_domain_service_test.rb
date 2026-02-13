# frozen_string_literal: true

require "test_helper"

class SesDomainServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @custom_domain = CustomDomain.create!(
      entity: @entity,
      user: @user,
      domain_name: 'sestest.com'
    )
    @service = SesDomainService.new(custom_domain: @custom_domain)
  end

  # ============================================
  # START VERIFICATION
  # ============================================

  test "start_verification returns dns records in development mode" do
    result = @service.start_verification

    assert result[:success]
    assert result[:dns_records].present?
    assert result[:instructions].present?
  end

  test "start_verification stores dns_records on the custom domain" do
    @service.start_verification

    @custom_domain.reload
    assert @custom_domain.dns_records.present?
  end

  # ============================================
  # CHECK VERIFICATION STATUS
  # ============================================

  test "check_verification_status auto-verifies in development" do
    @custom_domain.update!(email_status: 'verifying')

    result = @service.check_verification_status

    assert result[:success]
    assert result[:verified]
    assert_equal 'verified', @custom_domain.reload.email_status
  end

  # ============================================
  # BUILD DNS RECORDS
  # ============================================

  test "build_dns_records generates DKIM, SPF, DMARC, and MX records" do
    dkim_tokens = %w[token1 token2 token3]
    records = @service.send(:build_dns_records, dkim_tokens)

    assert_equal 3, records[:dkim].length
    assert records[:spf].present?
    assert records[:dmarc].present?
    assert records[:mail_from].present?
    assert records[:mail_from_spf].present?

    # Check DKIM format
    records[:dkim].each do |dkim|
      assert_equal 'CNAME', dkim[:type]
      assert dkim[:name].include?('._domainkey.')
      assert dkim[:value].include?('.dkim.amazonses.com')
    end

    # Check SPF
    assert_equal 'TXT', records[:spf][:type]
    assert_includes records[:spf][:value], 'amazonses.com'

    # Check DMARC
    assert_equal 'TXT', records[:dmarc][:type]
    assert_includes records[:dmarc][:name], '_dmarc'
  end

  # ============================================
  # AUTO CONFIGURE EMAIL DNS (Fixed service ref)
  # ============================================

  test "auto_configure_email_dns skips when no GoDaddy connection" do
    dns_records = { dkim: [], spf: { value: 'test' } }

    # Should not raise -- just returns early
    assert_nothing_raised do
      @service.send(:auto_configure_email_dns, dns_records)
    end
  end

  test "auto_configure_email_dns uses IntegrationApiService when connected" do
    godaddy = Integration.create!(
      name: 'GoDaddy', slug: 'godaddy_ses_test', category: 'custom',
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

    # Associate GoDaddy connection with the custom domain
    @custom_domain.update!(connection: connection)

    dns_records = {
      dkim: [
        { type: 'CNAME', name: "tok1._domainkey.sestest.com", value: 'tok1.dkim.amazonses.com' }
      ],
      spf: { type: 'TXT', name: 'sestest.com', value: 'v=spf1 include:amazonses.com ~all' },
      dmarc: { type: 'TXT', name: '_dmarc.sestest.com', value: 'v=DMARC1; p=none;' },
      mail_from: { type: 'MX', name: 'mail.sestest.com', value: '10 feedback-smtp.us-east-1.amazonses.com' },
      mail_from_spf: { type: 'TXT', name: 'mail.sestest.com', value: 'v=spf1 include:amazonses.com ~all' }
    }

    # Stub IntegrationApiService
    mock_response = stub(success?: true, code: 200, body: '{}')
    IntegrationApiService.any_instance.stubs(:execute_operation).returns(mock_response)

    assert_nothing_raised do
      @service.send(:auto_configure_email_dns, dns_records)
    end
  end

  test "auto_configure_email_dns handles errors gracefully" do
    godaddy = Integration.create!(
      name: 'GoDaddy', slug: 'godaddy_ses_err', category: 'custom',
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
    @custom_domain.update!(connection: connection)

    dns_records = {
      dkim: [{ type: 'CNAME', name: "t._domainkey.sestest.com", value: 't.dkim.amazonses.com' }],
      spf: { type: 'TXT', name: 'sestest.com', value: 'v=spf1 include:amazonses.com ~all' }
    }

    IntegrationApiService.any_instance.stubs(:execute_operation).raises(StandardError.new("API down"))

    # Should not raise -- logs error instead
    assert_nothing_raised do
      @service.send(:auto_configure_email_dns, dns_records)
    end
  end

  # ============================================
  # SEND EMAIL
  # ============================================

  test "send_email requires verified domain" do
    result = @service.send_email(
      from_address: 'hello@sestest.com',
      to_addresses: ['user@example.com'],
      subject: 'Test',
      body_html: '<p>Test</p>'
    )

    assert_not result[:success]
    assert_includes result[:error], 'not verified'
  end

  test "send_email validates from_address matches domain" do
    @custom_domain.update!(email_status: 'verified', email_verified_at: Time.current)

    result = @service.send_email(
      from_address: 'hello@otherdomain.com',
      to_addresses: ['user@example.com'],
      subject: 'Test',
      body_html: '<p>Test</p>'
    )

    assert_not result[:success]
    assert_includes result[:error], 'must use domain'
  end

  test "send_email works in development mode" do
    @custom_domain.update!(email_status: 'verified', email_verified_at: Time.current)

    result = @service.send_email(
      from_address: 'hello@sestest.com',
      to_addresses: ['user@example.com'],
      subject: 'Test',
      body_html: '<p>Test</p>'
    )

    assert result[:success]
    assert result[:message_id].present?
    assert_equal 'development', result[:mode]
  end
end
