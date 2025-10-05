class Admin::IntegrationOperationsController < Admin::BaseController
  before_action :set_integration
  before_action :set_operation, only: [:show, :edit, :update, :destroy]
  
  def index
    @operations = @integration.integration_operations.order(:operation_id)
  end
  
  def show
  end
  
  def new
    @operation = @integration.integration_operations.build
  end
  
  def create
    @operation = @integration.integration_operations.build(operation_params)
    
    if @operation.save
      redirect_to admin_integration_path(@integration), notice: 'Operation created successfully.'
    else
      render :new
    end
  end
  
  def edit
  end
  
  def update
    if @operation.update(operation_params)
      redirect_to admin_integration_path(@integration), notice: 'Operation updated successfully.'
    else
      render :edit
    end
  end
  
  def destroy
    @operation.destroy
    redirect_to admin_integration_path(@integration), notice: 'Operation deleted successfully.'
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
      :name, :operation_id, :description, :http_method, :path_template,
      :pagination_strategy, :is_idempotent, :requires_confirmation, :max_limit,
      :documentation, :examples, :version, :request_schema, :response_schema
    )
  end
end

