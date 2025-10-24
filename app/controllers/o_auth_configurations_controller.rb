class OAuthConfigurationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_oauth_configuration, only: [:edit, :update, :destroy]

  def index
    @oauth_configurations = current_entity.oauth_configurations.includes(:integration).order(:created_at)
    @integrations_needing_config = Integration.oauth2_custom.active - @oauth_configurations.map(&:integration)
  end

  def new
    @integration = Integration.find(params[:integration_id])
    @oauth_configuration = current_entity.oauth_configurations.build(integration: @integration)
    
    # Pre-populate with integration defaults
    if @integration.auth_config.present?
      config = @integration.auth_config
      @oauth_configuration.assign_attributes(
        authorize_url: config['authorize_url'],
        token_url: config['token_url'],
        scopes_array: config['scopes'] || [],
        redirect_uri: "#{request.base_url}/integrations/callback/#{@integration.slug}"
      )
    end
  end

  def create
    @oauth_configuration = current_entity.oauth_configurations.build(oauth_configuration_params)
    
    if @oauth_configuration.save
      redirect_to oauth_configurations_path, notice: "OAuth configuration created successfully!"
    else
      @integration = @oauth_configuration.integration
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @oauth_configuration.update(oauth_configuration_params)
      redirect_to oauth_configurations_path, notice: "OAuth configuration updated successfully!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @oauth_configuration.destroy
    redirect_to oauth_configurations_path, notice: "OAuth configuration deleted successfully!"
  end

  private

  def set_oauth_configuration
    @oauth_configuration = current_entity.oauth_configurations.find(params[:id])
  end

  def oauth_configuration_params
    params.require(:oauth_configuration).permit(
      :integration_id, :client_id, :client_secret, :redirect_uri, 
      :authorize_url, :token_url, :scopes, :credentials
    )
  end
end
