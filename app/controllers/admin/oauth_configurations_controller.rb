class Admin::OauthConfigurationsController < Admin::BaseController
  before_action :authorize_editor!
  before_action :set_integration, only: [:new, :create]
  before_action :set_oauth_configuration, only: [:show, :edit, :update, :destroy]

  def index
    @oauth_configurations = OauthConfiguration.includes(:integration)
                                               .order(created_at: :desc)
                                               .page(params[:page])

    @stats = {
      total: OauthConfiguration.count,
      active: OauthConfiguration.active.count,
      integrations_configured: OauthConfiguration.distinct.count(:integration_id)
    }
  end

  def show
  end

  def new
    # Check if OAuth config already exists for this integration
    existing_config = OauthConfiguration.find_by(integration: @integration)
    if existing_config
      redirect_to edit_admin_integration_oauth_configuration_path(@integration, existing_config),
                  notice: "An OAuth configuration already exists for #{@integration.name}. You can edit it here."
      return
    end
    
    @oauth_configuration = OauthConfiguration.new(integration: @integration)
    
    # Pre-fill with integration defaults
    @oauth_configuration.redirect_uri = "https://app.agentmarketing.com/integrations/callback/#{@integration.slug}"
    @oauth_configuration.authorize_url = @integration.auth_config["authorize_url"]
    @oauth_configuration.token_url = @integration.auth_config["token_url"]
    @oauth_configuration.scopes = @integration.auth_config["scopes"]&.join(", ")
  end

  def create
    @oauth_configuration = OauthConfiguration.new(oauth_configuration_params)
    @oauth_configuration.integration = @integration

    if @oauth_configuration.save
      redirect_to admin_integration_path(@integration),
                  notice: "OAuth configuration was successfully created for #{@integration.name}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @integration = @oauth_configuration.integration
  end

  def update
    if @oauth_configuration.update(oauth_configuration_params)
      redirect_to admin_integration_path(@oauth_configuration.integration),
                  notice: "OAuth configuration was successfully updated."
    else
      @integration = @oauth_configuration.integration
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    integration = @oauth_configuration.integration
    @oauth_configuration.destroy
    redirect_to admin_integration_path(integration),
                notice: "OAuth configuration was successfully deleted."
  end

  private

  def set_integration
    @integration = Integration.find(params[:integration_id])
  end

  def set_oauth_configuration
    @oauth_configuration = OauthConfiguration.find(params[:id])
  end

  def oauth_configuration_params
    params.require(:oauth_configuration).permit(
      :client_id, :client_secret, :redirect_uri, :scopes, :status,
      :authorize_url, :token_url, credentials: {}, metadata: {}
    )
  end

  def authorize_editor!
    authorize_admin!(:editor)
  end
end

