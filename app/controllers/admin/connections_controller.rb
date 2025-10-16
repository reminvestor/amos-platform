class Admin::ConnectionsController < Admin::BaseController
  before_action :set_connection, only: [ :show ]

  def index
    @connections = Connection.includes(:integration, :entity)
                             .order(created_at: :desc)
                             .page(params[:page])
  end

  def show
    # Preload integration_operation for logs to avoid N+1 queries
    @connection = Connection.includes(integration_logs: :integration_operation).find(params[:id])
  end

  # Admin actions removed for security:
  # - No edit/update (customers manage their own connections)
  # - No test (would use customer credentials)
  # - No refresh (would modify customer data)
  # - No destroy (customers control their own connections)
  #
  # Admins can only VIEW connection metadata for monitoring purposes

  private

  def set_connection
    @connection = Connection.find(params[:id])
  end

  def connection_params
    params.require(:connection).permit(:name, :status, :config)
  end
end
