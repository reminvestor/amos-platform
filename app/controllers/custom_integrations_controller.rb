class CustomIntegrationsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin_or_owner!

  def new
    @integration = Integration.new
  end

  def create
    @integration = Integration.new(integration_params)
    @integration.is_verified = false  # Custom integrations start unverified
    @integration.is_active = true

    # Parse allowed hosts from the API base URL
    if @integration.api_base_url.present?
      begin
        uri = URI.parse(@integration.api_base_url)
        @integration.allowed_hosts = [ uri.host ]
      rescue URI::InvalidURIError
        @integration.errors.add(:api_base_url, "is not a valid URL")
      end
    end

    if @integration.save
      # Create a default test operation
      @integration.integration_operations.create!(
        operation_id: "#{@integration.slug}.test.v1",
        name: "Test Connection",
        description: "Test if the API credentials are working",
        http_method: "GET",
        path_template: @integration.auth_config["test_endpoint"] || "/",
        is_idempotent: true,
        requires_confirmation: false,
        request_schema: {},
        response_schema: {}
      )

      redirect_to integration_operations_path(@integration),
                  notice: "Custom integration created! Now add some operations."
    else
      render :new
    end
  end

  private

  def integration_params
    params.require(:integration).permit(
      :name, :slug, :category, :description,
      :auth_type, :api_base_url, :documentation_url, :icon_url,
      auth_config: {}
    ).tap do |whitelisted|
      # Convert auth_config to proper format
      if params[:integration][:auth_config].present?
        whitelisted[:auth_config] = params[:integration][:auth_config].to_unsafe_h
      end
    end
  end

  def require_admin_or_owner!
    unless current_user.admin? || current_entity.owner?(current_user)
      redirect_to root_path, alert: "You need admin privileges to create custom integrations."
    end
  end
end
