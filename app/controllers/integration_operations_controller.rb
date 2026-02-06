class IntegrationOperationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_integration
  before_action :require_admin_or_owner!
  before_action :set_operation, only: [ :edit, :update, :destroy ]

  def index
    @operations = @integration.integration_operations.order(:operation_id)
  end

  def new
    @operation = @integration.integration_operations.build

    # Pre-fill common patterns based on HTTP method
    if params[:template].present?
      case params[:template]
      when "list"
        @operation.assign_attributes(
          http_method: "GET",
          pagination_strategy: "cursor",
          is_idempotent: true,
          requires_confirmation: false,
          request_schema: {
            type: "object",
            properties: {
              limit: { type: "integer", minimum: 1, maximum: 100 },
              cursor: { type: "string" }
            }
          }
        )
      when "get"
        @operation.assign_attributes(
          http_method: "GET",
          path_template: "/resource/{id}",
          is_idempotent: true,
          requires_confirmation: false
        )
      when "create"
        @operation.assign_attributes(
          http_method: "POST",
          is_idempotent: false,
          requires_confirmation: true
        )
      when "update"
        @operation.assign_attributes(
          http_method: "PUT",
          path_template: "/resource/{id}",
          is_idempotent: true,
          requires_confirmation: true
        )
      when "delete"
        @operation.assign_attributes(
          http_method: "DELETE",
          path_template: "/resource/{id}",
          is_idempotent: true,
          requires_confirmation: true
        )
      end
    end
  end

  def create
    @operation = @integration.integration_operations.build(operation_params)

    # Auto-generate operation_id if not provided
    if @operation.operation_id.blank?
      @operation.operation_id = generate_operation_id(@operation)
    end

    if @operation.save
      redirect_to integration_operations_path(@integration),
                  notice: "Operation added successfully!"
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @operation.update(operation_params)
      redirect_to integration_operations_path(@integration),
                  notice: "Operation updated successfully!"
    else
      render :edit
    end
  end

  def destroy
    @operation.destroy
    redirect_to integration_operations_path(@integration),
                notice: "Operation removed."
  end

  # Test an operation with sample data
  def test
    @operation = @integration.integration_operations.find(params[:id])

    # Check if user has a connection
    connection = current_entity.connections.find_by(integration: @integration)

    if connection.nil?
      redirect_back fallback_location: integration_operations_path(@integration),
                    alert: "You need to connect this integration first."
      return
    end

    # Execute integration action directly via V3 tool
    tool = V3::Tools::PlatformExecuteTool.new(
      user: current_user,
      entity: current_entity,
      context: {}
    )
    result = tool.execute({
      "action" => "integration",
      "integration" => connection.integration&.slug,
      "operation" => @operation.operation_id,
      "inputs" => params[:test_params] || {}
    })

    respond_to do |format|
      format.json { render json: result }
    end
  end

  private

  def set_integration
    @integration = Integration.find(params[:integration_id])
  end

  def set_operation
    @operation = @integration.integration_operations.find(params[:id])
  end

  def operation_params
    params.require(:integration_operation).permit(
      :operation_id, :name, :description, :http_method, :path_template,
      :pagination_strategy, :is_idempotent, :requires_confirmation,
      :max_limit, :documentation, :version
    ).tap do |whitelisted|
      # Handle JSON fields
      [ :request_schema, :response_schema, :examples ].each do |field|
        if params[:integration_operation][field].present?
          begin
            whitelisted[field] = JSON.parse(params[:integration_operation][field])
          rescue JSON::ParserError
            whitelisted[field] = {}
          end
        end
      end
    end
  end

  def require_admin_or_owner!
    # Only admins can edit verified integrations
    if @integration.is_verified && !current_user.admin?
      redirect_to root_path, alert: "Only admins can modify verified integrations."
      return
    end

    # For custom integrations, allow entity owners
    unless current_user.admin? || current_entity.owner?(current_user)
      redirect_to root_path, alert: "You need admin privileges."
    end
  end

  def generate_operation_id(operation)
    # Generate a reasonable operation_id
    method_prefix = operation.http_method.downcase
    name_part = operation.name.downcase.gsub(/\s+/, "_")
    "#{@integration.slug}.#{method_prefix}_#{name_part}.v1"
  end
end
