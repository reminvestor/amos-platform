# frozen_string_literal: true

require "test_helper"

class IntegrationCredentialSsoKeyTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)

    # Create a GoDaddy-like integration with sso-key auth
    @integration = Integration.create!(
      name: 'GoDaddy Test',
      slug: 'godaddy_test',
      category: 'custom',
      auth_type: 'api_key',
      api_base_url: 'https://api.godaddy.com',
      is_active: true,
      is_verified: true,
      auth_config: {
        'auth_method' => 'sso-key',
        'header_name' => 'Authorization',
        'header_template' => 'sso-key {api_key}:{api_secret}'
      }
    )

    @connection = Connection.create!(
      entity: @entity,
      integration: @integration,
      user: @user,
      name: 'GoDaddy Test Connection',
      status: :connected
    )
  end

  # ============================================
  # AuthConfig-based auth (primary path)
  # ============================================

  test "builds sso-key header via AuthConfig records" do
    # Create OauthConfiguration + AuthConfig (the primary auth path)
    oauth_config = OauthConfiguration.create!(
      integration: @integration,
      status: :active,
      test_endpoint: '/v1/domains'
    )

    oauth_config.auth_configs.create!(
      auth_key: 'Authorization',
      auth_value: 'sso-key {api_key}:{api_secret}',
      auth_placement: 'header',
      position: 1
    )

    credential = IntegrationCredential.create!(
      connection: @connection,
      name: 'GoDaddy API Key',
      auth_method: 'header',
      status: :active,
      credentials: { 'api_key' => 'mykey123', 'api_secret' => 'mysecret456' }
    )

    headers = credential.build_auth_header

    assert_equal({ 'Authorization' => 'sso-key mykey123:mysecret456' }, headers)
  end

  test "handles missing credential values gracefully in AuthConfig path" do
    oauth_config = OauthConfiguration.create!(
      integration: @integration,
      status: :active,
      test_endpoint: '/v1/domains'
    )

    oauth_config.auth_configs.create!(
      auth_key: 'Authorization',
      auth_value: 'sso-key {api_key}:{api_secret}',
      auth_placement: 'header',
      position: 1
    )

    credential = IntegrationCredential.create!(
      connection: @connection,
      name: 'GoDaddy Partial',
      auth_method: 'header',
      status: :active,
      credentials: { 'api_key' => 'onlykey' }
    )

    headers = credential.build_auth_header

    # Should still build the header, just with empty secret
    assert_equal({ 'Authorization' => 'sso-key onlykey:' }, headers)
  end

  # ============================================
  # Legacy fallback (safety net)
  # ============================================

  test "builds sso-key header via legacy fallback when no AuthConfig exists" do
    # No OauthConfiguration or AuthConfig records -- uses legacy fallback
    credential = IntegrationCredential.create!(
      connection: @connection,
      name: 'GoDaddy Legacy',
      auth_method: 'header',
      status: :active,
      credentials: { 'api_key' => 'legacykey', 'api_secret' => 'legacysecret' }
    )

    headers = credential.build_auth_header

    # Legacy fallback reads header_template from integration.auth_config
    assert_equal({ 'Authorization' => 'sso-key legacykey:legacysecret' }, headers)
  end

  test "legacy fallback uses plain header when no template" do
    # Integration without header_template -- standard api_key behavior
    plain_integration = Integration.create!(
      name: 'Plain API',
      slug: 'plain_test',
      category: 'custom',
      auth_type: 'api_key',
      api_base_url: 'https://api.example.com',
      is_active: true,
      is_verified: true,
      auth_config: {}
    )

    plain_connection = Connection.create!(
      entity: @entity,
      integration: plain_integration,
      user: @user,
      name: 'Plain Connection',
      status: :connected
    )

    credential = IntegrationCredential.create!(
      connection: plain_connection,
      name: 'Plain Key',
      auth_method: 'header',
      status: :active,
      credentials: { 'api_key' => 'simplekey' }
    )

    headers = credential.build_auth_header

    # Should fall back to standard header behavior
    assert headers.values.first.include?('simplekey')
  end
end
