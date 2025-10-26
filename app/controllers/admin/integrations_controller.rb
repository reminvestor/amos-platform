class Admin::IntegrationsController < Admin::BaseController
  before_action :authorize_editor!, except: [ :index, :show, :logs ]
  before_action :set_integration, only: [ :show, :edit, :update, :destroy, :discover_operations ]
  before_action :check_editor_for_discovery, only: [ :discover_operations ]

  def index
    @integrations = Integration.includes(:connections, :integration_operations)
                               .page(params[:page])

    @stats = {
      total: Integration.count,
      verified: Integration.where(is_verified: true).count,
      custom: Integration.where(is_verified: false).count,
      active_connections: Connection.active.count,
      connected_entities: Connection.active.distinct.count(:entity_id),
      api_calls_24h: IntegrationLog.where(created_at: 24.hours.ago..).count,
      error_rate: calculate_error_rate
    }
  end

  def show
    @connections = @integration.connections
                               .includes(:entity, :integration_credentials)
                               .order(created_at: :desc)
                               .page(params[:page])

    @operations = @integration.integration_operations
                              .order(:operation_id)

    respond_to do |format|
      format.html
      format.json { render json: @integration.as_json(include: [ :integration_operations, :connections ]) }
    end
  end

  def new
    @integration = Integration.new
  end

  def create
    @integration = Integration.new(integration_params)

    if @integration.save
      redirect_to admin_integration_path(@integration),
                  notice: "Integration was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @integration.update(integration_params)
      redirect_to admin_integration_path(@integration),
                  notice: "Integration was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @integration.destroy
    redirect_to admin_integrations_path,
                notice: "Integration was successfully deleted."
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
      when "success"
        @logs = @logs.where("response_status < 400")
      when "error"
        @logs = @logs.where("response_status >= 400")
      end
    end

    if params[:date_from].present?
      @logs = @logs.where("created_at >= ?", params[:date_from])
    end

    if params[:date_to].present?
      @logs = @logs.where("created_at <= ?", params[:date_to])
    end

    @logs = @logs.order(created_at: :desc).page(params[:page]).per(50)
  end
  
  def discover_operations
    # AI-powered operation discovery with full operation details as templates
    existing_operations = @integration.integration_operations.map do |op|
      [op.operation_id, op.name, op.path_template]
    end
    
    user_spec = params[:operation_spec] # Optional user-specified operations/endpoints
    
    # Start AI discovery job
    job = OperationDiscoveryJob.perform_later(
      @integration.id,
      current_user.id,
      existing_operations: existing_operations,
      user_specification: user_spec
    )
    
    respond_to do |format|
      format.html do
        redirect_to admin_integration_path(@integration), 
                    notice: "AI operation discovery started! The AI will research #{@integration.name}'s API and suggest new operations. You'll be notified when complete."
      end
      format.json do
        render json: { 
          success: true, 
          job_id: job.job_id,
          message: "Discovery started"
        }
      end
    end
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
  
  def check_editor_for_discovery
    authorize_admin!(:editor)
  end

  def calculate_error_rate
    total = IntegrationLog.where(created_at: 24.hours.ago..).count
    return 0 if total == 0

    errors = IntegrationLog.where(created_at: 24.hours.ago..)
                           .where("response_status >= 400").count

    ((errors.to_f / total) * 100).round(1)
  end
end
