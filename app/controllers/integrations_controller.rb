class IntegrationsController < ApplicationController
  before_action :authenticate_user!
  
  def index
    # Redirect to Scout with integrations canvas
    redirect_to scout_index_path(canvas: 'integrations_manager')
  end
  
  def connect
    @integration = Integration.find_by!(slug: params[:slug])
    
    case @integration.auth_type
    when 'oauth2', 'oauth2_custom'
      redirect_to integrations_oauth_authorize_path(@integration.slug)
    else
      # Show credentials form
      render :connect
    end
  end
  
  def create_connection
    @integration = Integration.find_by!(slug: params[:slug])
    
    # Create connection
    connection = current_entity.connections.find_or_initialize_by(
      integration: @integration
    )
    
    connection.name = params[:connection_name] || "#{@integration.name} - #{current_user.email}"
    connection.status = :connected
    
    if connection.save
      # Create credentials
      credential = connection.integration_credentials.build(
        name: params[:credential_name] || "API Credentials",
        credentials: build_credentials_from_params,
        auth_method: determine_auth_method,
        status: :active
      )
      
      if credential.save
        # Test connection
        test_result = connection.test_connection!
        
        if test_result[:success]
          respond_to do |format|
            format.html { redirect_to integrations_path, notice: "Successfully connected to #{@integration.name}!" }
            format.json { render json: { success: true, message: "Successfully connected to #{@integration.name}!" } }
          end
        else
          respond_to do |format|
            format.html { redirect_to integrations_path, alert: "Connected but test failed: #{test_result[:error]}" }
            format.json { render json: { success: false, error: "Connected but test failed: #{test_result[:error]}" } }
          end
        end
      else
        respond_to do |format|
          format.html { redirect_to connect_integration_path(@integration.slug), alert: "Failed to save credentials" }
          format.json { render json: { success: false, error: "Failed to save credentials" } }
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to connect_integration_path(@integration.slug), alert: "Failed to create connection" }
        format.json { render json: { success: false, error: "Failed to create connection" } }
      end
    end
  end
  
  private
  
  def build_credentials_from_params
    case @integration.auth_type
    when 'api_key'
      { api_key: params[:api_key] }
    when 'bearer_token'
      { token: params[:bearer_token] }
    when 'basic_auth'
      { 
        username: params[:username],
        password: params[:password]
      }
    when 'custom'
      # Handle custom auth based on integration
      case @integration.slug
      when 'slack'
        { webhook_url: params[:webhook_url] }
      else
        params.permit(:api_key, :token, :username, :password).to_h
      end
    else
      {}
    end
  end
  
  def determine_auth_method
    case @integration.auth_type
    when 'api_key'
      'header' # Usually goes in header
    when 'bearer_token'
      'bearer'
    when 'basic_auth'
      'basic'
    else
      'header'
    end
  end
end
