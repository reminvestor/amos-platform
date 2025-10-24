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
    
    # Pre-fill with integration defaults for OAuth
    if @integration.oauth?
      @oauth_configuration.redirect_uri = "https://app.agentmarketing.com/integrations/callback/#{@integration.slug}"
      @oauth_configuration.authorize_url = @integration.auth_config["authorize_url"]
      @oauth_configuration.token_url = @integration.auth_config["token_url"]
      @oauth_configuration.scopes = @integration.auth_config["scopes"]&.join(", ")
    else
      # Pre-populate with legacy auth config if it exists
      legacy_params = @integration.current_auth_params
      
      if legacy_params.any?
        legacy_params.each_with_index do |param, index|
          @oauth_configuration.auth_configs.build(
            auth_key: param[:key],
            auth_value: param[:value],
            auth_placement: param[:placement],
            position: index
          )
        end
      else
        # Build 3 empty auth_configs for manual entry
        3.times { @oauth_configuration.auth_configs.build }
      end
    end
  end

  def create
    @oauth_configuration = OauthConfiguration.new(oauth_configuration_params)
    @oauth_configuration.integration = @integration

    if @oauth_configuration.save
      redirect_to admin_integration_path(@integration),
                  notice: "Authentication configuration was successfully created for #{@integration.name}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @integration = @oauth_configuration.integration
    # Don't auto-create empty fields on edit - only show what exists
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
          :authorize_url, :token_url, :callback_params, :test_endpoint,
          credentials: {}, 
          metadata: {},
          auth_configs_attributes: [:id, :auth_key, :auth_value, :auth_placement, :position, :_destroy]
        ).tap do |whitelisted|
          # Convert callback_params from comma-separated string to array
          if whitelisted[:callback_params].is_a?(String)
            whitelisted[:callback_params] = whitelisted[:callback_params]
              .split(',')
              .map(&:strip)
              .reject(&:blank?)
          end
        end
      end

  def authorize_editor!
    authorize_admin!(:editor)
  end
end

