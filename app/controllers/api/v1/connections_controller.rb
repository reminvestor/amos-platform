module Api
  module V1
    class ConnectionsController < BaseController
      before_action :set_connection, only: [:show, :destroy, :test]

      def index
        @connections = current_entity.connections.includes(:integration)

        render json: {
          data: @connections.map { |c| connection_json(c) }
        }
      end

      def show
        render json: connection_json(@connection)
      end

      def test
        result = @connection.test_connection!

        render json: {
          success: result[:success],
          message: result[:success] ? 'Connection is healthy' : result[:error],
          status: @connection.status
        }
      end

      def destroy
        @connection.destroy!
        head :no_content
      end

      # List available integrations that can be connected
      def available
        integrations = Integration.where(is_active: true).order(:name)

        render json: {
          data: integrations.map { |i| integration_json(i) }
        }
      end

      # Get OAuth authorization URL for mobile
      # GET /api/v1/connections/oauth_url/:slug
      def oauth_url
        integration = Integration.find_by!(slug: params[:slug])

        unless integration.oauth?
          return render json: { error: "This integration does not support OAuth" }, status: :unprocessable_entity
        end

        oauth_config = OauthConfiguration.find_by(integration: integration)
        unless oauth_config
          return render json: { error: "OAuth not configured for this integration" }, status: :unprocessable_entity
        end

        credentials = oauth_config.credentials

        # Generate state token for security
        oauth_state = SecureRandom.hex(16)
        oauth_data = {
          integration_id: integration.id,
          user_id: current_user.id,
          entity_id: current_entity.id,
          from_mobile: true
        }

        # Store state in cache with 10 minute expiry
        Rails.cache.write("oauth_state:#{oauth_state}", oauth_data, expires_in: 10.minutes)

        # Build authorization URL
        url_params = {
          client_id: credentials["client_id"],
          redirect_uri: credentials["redirect_uri"],
          response_type: "code",
          state: oauth_state,
          scope: credentials["scopes"]&.join(" ") || credentials["scope"],
          access_type: credentials["access_type"] || "offline"
        }

        uri = URI(credentials["authorize_url"])
        uri.query = url_params.to_query

        render json: {
          url: uri.to_s,
          state: oauth_state,
          integration: {
            name: integration.name,
            slug: integration.slug
          }
        }
      end

      private

      def set_connection
        @connection = current_entity.connections.find(params[:id])
      end

      def connection_json(connection)
        {
          id: connection.id,
          name: connection.name,
          status: connection.status,
          integration: {
            id: connection.integration.id,
            name: connection.integration.name,
            slug: connection.integration.slug,
            icon: connection.integration.icon_url,
            description: connection.integration.description,
            category: connection.integration.category
          },
          last_health_check: connection.last_health_check&.iso8601,
          created_at: connection.created_at.iso8601,
          updated_at: connection.updated_at.iso8601
        }
      end

      def integration_json(integration)
        {
          id: integration.id,
          name: integration.name,
          slug: integration.slug,
          icon: integration.icon_url,
          description: integration.description,
          category: integration.category,
          auth_type: integration.auth_type,
          is_active: integration.is_active,
          # Check if entity already has a connection
          connected: current_entity.connections.exists?(integration: integration)
        }
      end
    end
  end
end
