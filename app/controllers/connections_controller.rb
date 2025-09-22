class ConnectionsController < ApplicationController
  before_action :authenticate_user!
  include EntityScoped

  # POST /connections/:id/test
  def test
    connection = current_entity.connections.find_by(id: params[:id])
    return render json: { success: false, error: 'Connection not found' }, status: :not_found unless connection

    result = connection.test_connection!
    render json: result.merge(success: result[:success])
  rescue => e
    render json: { success: false, error: e.message }, status: :internal_server_error
  end

  # GET /connections/:id/operations
  def operations
    connection = current_entity.connections.includes(:integration => :integration_operations).find_by(id: params[:id])
    return render json: { success: false, error: 'Connection not found' }, status: :not_found unless connection

    ops = connection.available_operations.order(:name).map do |op|
      {
        id: op.id,
        operation_id: op.operation_id,
        name: op.name,
        http_method: op.http_method,
        path_template: op.path_template,
        requires_confirmation: op.requires_confirmation,
        pagination_strategy: op.pagination_strategy,
        example: op.format_example_request
      }
    end

    render json: {
      success: true,
      connection: { id: connection.id, name: connection.name },
      integration: { 
        id: connection.integration.id, 
        name: connection.integration.name, 
        slug: connection.integration.slug,
        auth_type: connection.integration.auth_type,
        auth_config: connection.integration.auth_config
      },
      operations: ops
    }
  end

  # PATCH /connections/:id/credentials
  def update_credentials
    connection = current_entity.connections.includes(:integration, :integration_credentials).find_by(id: params[:id])
    return render json: { success: false, error: 'Connection not found' }, status: :not_found unless connection

    integration = connection.integration
    credential = connection.active_credential || connection.integration_credentials.build(name: 'API Credentials')

    # Build credentials based on integration auth type
    creds = case integration.auth_type
            when 'api_key'
              { 'api_key' => params[:api_key] }
            when 'bearer_token'
              { 'token' => params[:bearer_token] }
            when 'basic_auth'
              { 'username' => params[:username], 'password' => params[:password] }
            else
              params.permit(:api_key, :token, :username, :password, :webhook_url).to_h.stringify_keys
            end

    # Ensure credentials is a hash, not a string
    existing_creds = credential.credentials
    if existing_creds.is_a?(String)
      begin
        existing_creds = JSON.parse(existing_creds)
      rescue JSON::ParserError
        existing_creds = {}
      end
    end
    existing_creds ||= {}
    
    credential.credentials = existing_creds.merge(creds.compact)
    credential.auth_method = determine_auth_method(integration)
    credential.status = :active
    credential.save!

    render json: { success: true, message: 'Credentials updated successfully' }
  rescue => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  private

  def determine_auth_method(integration)
    case integration.auth_type
    when 'api_key'
      'header'
    when 'bearer_token'
      'bearer'
    when 'basic_auth'
      'basic'
    else
      'header'
    end
  end
end


