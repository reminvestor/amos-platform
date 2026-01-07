# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class ConnectionsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @entity = entities(:one)
        @user.update!(entity: @entity, api_key: SecureRandom.hex(32))

        # Create test integration
        @integration = Integration.create!(
          name: "Test Integration",
          slug: "test_integration",
          description: "A test integration",
          category: "crm",
          auth_type: "api_key",
          api_base_url: "https://api.testintegration.com",
          is_active: true
        )

        @inactive_integration = Integration.create!(
          name: "Inactive Integration",
          slug: "inactive_integration",
          description: "An inactive integration",
          category: "communication",
          auth_type: "oauth2",
          api_base_url: "https://api.inactive.com",
          is_active: false
        )

        # Create test connection
        @connection = Connection.create!(
          entity: @entity,
          user: @user,
          integration: @integration,
          name: "My Test Connection",
          status: "connected"
        )
      end

      teardown do
        Connection.where(entity: @entity).destroy_all
        Integration.where(slug: %w[test_integration inactive_integration]).destroy_all
      end

      # ====================================================================
      # Helper Methods
      # ====================================================================

      def auth_headers
        { "Authorization" => "Bearer #{@user.api_key}" }
      end

      # ====================================================================
      # INDEX Tests
      # ====================================================================

      test "should get connections list with valid token" do
        get api_v1_connections_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("data")
      end

      test "connections list returns expected fields" do
        get api_v1_connections_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        connections = response_body["data"]

        assert connections.any?

        connection = connections.find { |c| c["id"] == @connection.id }
        assert_not_nil connection
        assert_equal "My Test Connection", connection["name"]
        assert_equal "connected", connection["status"]
        assert connection.key?("integration")
        assert_equal @integration.id, connection["integration"]["id"]
        assert_equal "Test Integration", connection["integration"]["name"]
        assert connection.key?("created_at")
        assert connection.key?("updated_at")
      end

      test "connections list requires authentication" do
        get api_v1_connections_path, as: :json

        assert_response :unauthorized
      end

      test "connections list rejects invalid token" do
        get api_v1_connections_path,
          headers: { "Authorization" => "Bearer invalid_token" },
          as: :json

        assert_response :unauthorized
      end

      test "connections list only returns current entity connections" do
        other_entity = entities(:two)
        other_user = users(:two)
        other_user.update!(entity: other_entity, api_key: SecureRandom.hex(32))

        other_connection = Connection.create!(
          entity: other_entity,
          user: other_user,
          integration: @integration,
          name: "Other Entity Connection",
          status: "connected"
        )

        get api_v1_connections_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        connection_ids = response_body["data"].map { |c| c["id"] }

        assert_includes connection_ids, @connection.id
        assert_not_includes connection_ids, other_connection.id

        other_connection.destroy
      end

      # ====================================================================
      # SHOW Tests
      # ====================================================================

      test "should get connection details with valid token" do
        get api_v1_connection_path(@connection), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal @connection.id, response_body["id"]
        assert_equal "My Test Connection", response_body["name"]
        assert_equal "connected", response_body["status"]
      end

      test "should return 404 for non-existent connection" do
        get api_v1_connection_path(id: 999999), headers: auth_headers, as: :json

        assert_response :not_found
      end

      test "connection show requires authentication" do
        get api_v1_connection_path(@connection), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # TEST Tests
      # ====================================================================

      test "should test connection" do
        # Mock the test_connection! method
        Connection.any_instance.stubs(:test_connection!).returns({ success: true })

        post test_api_v1_connection_path(@connection), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("success")
        assert response_body.key?("status")
      end

      test "test connection requires authentication" do
        post test_api_v1_connection_path(@connection), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # DESTROY Tests
      # ====================================================================

      test "should destroy connection" do
        assert_difference("Connection.count", -1) do
          delete api_v1_connection_path(@connection), headers: auth_headers, as: :json
        end

        assert_response :no_content
      end

      test "should return 404 when destroying non-existent connection" do
        delete api_v1_connection_path(id: 999999), headers: auth_headers, as: :json

        assert_response :not_found
      end

      test "destroy connection requires authentication" do
        delete api_v1_connection_path(@connection), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # AVAILABLE Tests
      # ====================================================================

      test "should get available integrations" do
        get available_api_v1_connections_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("data")

        integrations = response_body["data"]
        integration_ids = integrations.map { |i| i["id"] }

        # Should include active integrations
        assert_includes integration_ids, @integration.id
        # Should not include inactive integrations
        assert_not_includes integration_ids, @inactive_integration.id
      end

      test "available integrations show connected status" do
        get available_api_v1_connections_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        integration = response_body["data"].find { |i| i["id"] == @integration.id }

        assert_not_nil integration
        assert_equal true, integration["connected"]  # We have a connection to this integration
      end

      test "available integrations requires authentication" do
        get available_api_v1_connections_path, as: :json

        assert_response :unauthorized
      end
    end
  end
end
