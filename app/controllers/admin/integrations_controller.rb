class Admin::IntegrationsController < Admin::BaseController
  before_action :authorize_editor!, except: [:index, :show, :logs]
  before_action :set_integration, only: [:show, :edit, :update, :destroy]
  
  def index
    @integrations = Integration.includes(:connections, :integration_operations)
                               .page(params[:page])
    
    @stats = {
      total_integrations: Integration.count,
      active_integrations: Integration.active.count,
      verified_integrations: Integration.verified.count,
      total_connections: Connection.count,
      active_connections: Connection.active.count
    }
  end
  
  def show
    @connections = @integration.connections
                               .includes(:entity, :integration_credentials)
                               .order(created_at: :desc)
                               .page(params[:page])
    
    @operations = @integration.integration_operations
                              .order(:operation_id)
  end
  
  def new
    @integration = Integration.new
  end
  
  def create
    @integration = Integration.new(integration_params)
    
    if @integration.save
      redirect_to admin_integration_path(@integration), 
                  notice: 'Integration was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
  end
  
  def update
    if @integration.update(integration_params)
      redirect_to admin_integration_path(@integration), 
                  notice: 'Integration was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    @integration.destroy
    redirect_to admin_integrations_path, 
                notice: 'Integration was successfully deleted.'
  end
  
  def logs
    @logs = IntegrationLog.includes(:connection, :user, :integration_operation)
    
    # Filters
    if params[:integration_id].present?
      integration = Integration.find(params[:integration_id])
      connection_ids = integration.connections.pluck(:id)
      @logs = @logs.where(connection_id: connection_ids)
    end
    
    if params[:user_id].present?
      @logs = @logs.where(user_id: params[:user_id])
    end
    
    if params[:status].present?
      case params[:status]
      when 'success'
        @logs = @logs.where('response_status < 400')
      when 'error'
        @logs = @logs.where('response_status >= 400')
      end
    end
    
    if params[:date_from].present?
      @logs = @logs.where('created_at >= ?', params[:date_from])
    end
    
    if params[:date_to].present?
      @logs = @logs.where('created_at <= ?', params[:date_to])
    end
    
    @logs = @logs.order(created_at: :desc).page(params[:page]).per(50)
  end
  
  private
  
  def set_integration
    @integration = Integration.find(params[:id])
  end
  
  def integration_params
    params.require(:integration).permit(
      :name, :slug, :category, :auth_type, :api_base_url,
      :documentation_url, :icon_url, :description,
      :is_active, :is_verified,
      auth_config: {},
      allowed_hosts: [],
      metadata: {}
    )
  end
  
  def authorize_editor!
    authorize_admin!(:editor)
  end
end
