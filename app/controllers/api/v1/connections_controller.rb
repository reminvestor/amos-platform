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
            icon: connection.integration.icon,
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
          icon: integration.icon,
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
